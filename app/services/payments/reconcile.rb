module Payments
  class Reconcile
    def initialize(client: StripeClient.new)
      @client = client
    end

    def call(purchase)
      read_at = Time.current
      # Every Stripe read happens before any row lock, so a slow Stripe response
      # never blocks the buyer's sign-in, admin edits or parallel checkouts.
      @client.verify_account!(purchase)
      raise Error, "Checkout session missing" if purchase.checkout_session_id.blank?
      session = @client.request(:get, "/checkout/sessions/#{purchase.checkout_session_id}", { expand: [ "payment_intent.latest_charge" ] })
      validate_session!(purchase, session)
      disputes = fetch_disputes!(purchase, session) if session["payment_status"] == "paid"

      # Same buyer lock serializes separate attempts and return/webhook races.
      purchase.user.with_lock do
        purchase.with_lock do
          # Compare-and-write: a reconcile that read Stripe after us has already
          # written newer state; applying our older snapshot could undo it.
          next if purchase.reconciled_at && purchase.reconciled_at > read_at
          purchase.reconciled_at = read_at
          if session["status"] == "expired" && purchase.payment_state == "pending"
            purchase.payment_state = "expired"
          end
          if session["payment_status"] == "paid"
            reconcile_paid!(purchase, session, disputes)
          elsif purchase.fulfilled_at.nil?
            purchase.fulfilment_state = "pending"
            purchase.exception_reason = nil
          end
          if purchase.fulfilled_at
            purchase.fulfilment_state = "fulfilled"
            purchase.exception_reason = nil
          end
          purchase.save!
        end
      end
      purchase
    rescue Error => e
      # Reload first: the rolled-back transaction leaves partial reconcile state
      # (reconciled_at, totals, refunds) dirty in memory, which must not be saved.
      purchase.reload.update!(fulfilment_state: "exception", exception_reason: e.message)
      raise
    end

    private

    def validate_session!(purchase, session)
      metadata = session.fetch("metadata", {})
      valid = session["id"] == purchase.checkout_session_id && session["mode"] == "payment" &&
        session["livemode"] == purchase.livemode && session["currency"] == purchase.currency &&
        session["client_reference_id"] == purchase.attempt_key &&
        metadata["purchase_id"] == purchase.id.to_s && metadata["user_id"] == purchase.user_id.to_s &&
        metadata["course_id"] == purchase.course_id.to_s && metadata["attempt_key"] == purchase.attempt_key &&
        session.dig("automatic_tax", "enabled") == (purchase.tax_mode == "automatic")
      raise Error, "Checkout identity mismatch" unless valid
      return unless session["payment_status"] == "paid"
      items = @client.request(:get, "/checkout/sessions/#{purchase.checkout_session_id}/line_items")
      raise Error, "Checkout line item mismatch" unless items.fetch("data").length == 1
      item = items.fetch("data").first
      price = item.fetch("price")
      valid_price = !items["has_more"] && item["quantity"] == 1 && price["unit_amount"] == purchase.amount_minor &&
        price["currency"] == purchase.currency && price["tax_behavior"] == purchase.tax_behavior
      tax = session.dig("total_details", "amount_tax")
      total = session["amount_total"]
      expected = purchase.amount_minor + (purchase.tax_behavior == "exclusive" ? tax.to_i : 0)
      raise Error, "Checkout amount mismatch" unless valid_price && tax.is_a?(Integer) && total == expected &&
        session.dig("total_details", "amount_discount").to_i.zero? && session.dig("total_details", "amount_shipping").to_i.zero?
      raise Error, "Unexpected tax" if purchase.tax_mode == "exempt" && tax != 0
      raise Error, "Tax calculation incomplete" if purchase.tax_mode == "automatic" && session.dig("automatic_tax", "status") != "complete"
    end

    def fetch_disputes!(purchase, session)
      intent = session.fetch("payment_intent")
      charge = intent.fetch("latest_charge")
      raise Error, "Payment not captured" unless intent["status"] == "succeeded" && charge["paid"] && charge["captured"] &&
        charge["currency"] == purchase.currency && charge["amount"] == session["amount_total"] && charge["livemode"] == purchase.livemode
      # Checkout is card only; any other method is flagged for review, never granted.
      raise Error, "Unsupported payment method" unless charge.dig("payment_method_details", "type") == "card"
      disputes = @client.request(:get, "/disputes", { charge: charge.fetch("id"), limit: 100 })
      raise Error, "Dispute history requires review" if disputes["has_more"]
      disputes
    end

    def reconcile_paid!(purchase, session, disputes)
      intent = session.fetch("payment_intent")
      charge = intent.fetch("latest_charge")
      purchase.payment_intent_id = intent.fetch("id")
      purchase.tax_minor = session.dig("total_details", "amount_tax")
      purchase.total_minor = session.fetch("amount_total")
      purchase.base_minor = purchase.total_minor - purchase.tax_minor
      purchase.refunded_minor = [ purchase.refunded_minor, charge.fetch("amount_refunded") ].max
      statuses = disputes.fetch("data").map { |d| d.fetch("status") }
      grant = purchase.course_entitlement
      if purchase.refunded_minor >= purchase.total_minor
        purchase.payment_state = "refunded"
        transition(grant, "revoke", "stripe_full_refund", purchase)
      elsif statuses.include?("lost")
        purchase.payment_state = "lost"
        transition(grant, "revoke", "stripe_dispute_lost", purchase)
      elsif (statuses - %w[won warning_closed]).any?
        purchase.payment_state = "disputed"
        transition(grant, "suspend", "stripe_dispute", purchase)
      else
        # A late success must never resurrect a refunded/lost purchase.
        return if %w[refunded lost].include?(purchase.payment_state)
        purchase.payment_state = "paid"
        transition(grant, "restore", "stripe_dispute_won", purchase) if grant&.status == "suspended"
        fulfil!(purchase) unless purchase.fulfilled_at
      end
    end

    def transition(grant, action, reason, purchase)
      return unless grant
      Entitlements::Transition.call(grant: grant, action: action, source: "stripe", reason: reason, reference: purchase.attempt_key)
    end

    def fulfil!(purchase)
      course = purchase.course
      course.with_lock do
        unless course.published? && purchase.eligibility["eligible"] == true
          purchase.fulfilment_state = "exception"
          purchase.exception_reason = "course_unavailable"
          return
        end
        # Include grants without a purchase (SQL NOT IN alone excludes NULL).
        unless course.paid?
          purchase.fulfilment_state = "exception"
          purchase.exception_reason = "course_now_free_review_refund"
          return
        end
        other = CourseEntitlement.effective.where(user_id: purchase.user_id, course_id: course.id)
          .where("purchase_id IS NULL OR purchase_id <> ?", purchase.id)
        if other.exists?
          purchase.fulfilment_state = "exception"
          purchase.exception_reason = "duplicate_access_payment_review_refund"
          return
        end
        Entitlements::Grant.call(user: purchase.user, course: course, source: "stripe", reference: purchase.attempt_key,
          reason: "stripe_payment", purchase: purchase)
        enrollment = Enrollment.find_or_initialize_by(user_id: purchase.user_id, course_id: course.id)
        enrollment.skip_prerequisite_check = true # Only after verified payment + recorded eligibility.
        enrollment.archived_at = nil
        enrollment.save!
        purchase.fulfilled_at = Time.current
        purchase.fulfilment_state = "fulfilled"
        purchase.exception_reason = nil
      end
    end
  end
end
