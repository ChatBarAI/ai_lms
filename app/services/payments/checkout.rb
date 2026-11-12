module Payments
  class Checkout
    def initialize(client: StripeClient.new)
      @client = client
    end

    def call(user:, course:)
      raise CanCan::AccessDenied unless Ability.new(user).can?(:read, course) && course.published?
      return nil if CourseAccess.allowed?(user, course)
      raise Error, I18n.t("payments.unavailable") unless Configuration.checkout_ready?
      raise Error, I18n.t("payments.prerequisites") unless course.prerequisites_met_by?(user)
      settings = SiteSetting.current
      raise Error, "Reprice this course in the configured currency" unless course.price_currency == settings.payment_currency
      raise Error, "Invalid price" unless Currency.valid_amount?(course.price_currency, course.price_minor)

      # A reused attempt may be stale (repriced, tax/URL settings changed) or stuck
      # (ambiguous timeout past Stripe's idempotency window). Retire it safely and
      # start one fresh attempt rather than charging old terms or blocking forever.
      2.times do
        purchase = pending_purchase(user, course, settings)
        return nil unless purchase
        if current_terms?(purchase, course, settings) && !ambiguous?(purchase)
          ensure_session(purchase)
          return purchase unless purchase.payment_state == "expired" || ambiguous?(purchase)
          next if purchase.payment_state == "expired"
        end
        return reconcile_completed(purchase) if retire(purchase) == :complete
      end
      raise Error, I18n.t("payments.unavailable")
    end

    def ensure_session(purchase)
      purchase.with_lock do
        return unless purchase.payment_state == "pending"
        @client.verify_account!(purchase)
        if purchase.checkout_session_id.present?
          session = @client.request(:get, "/checkout/sessions/#{purchase.checkout_session_id}")
          if session["status"] != "open"
            purchase.checkout_url = nil
          end
          if session["status"] == "expired"
            purchase.update!(payment_state: "expired")
          end
          purchase.save!
          return session
        end
        # Stripe may prune idempotency keys after 24h. Do not risk a second charge
        # by replaying an ambiguous request outside that window.
        if purchase.created_at < 23.hours.ago
          session = recover_session(purchase)
          if session
            purchase.update!(checkout_session_id: session.fetch("id"), checkout_url: session["url"],
              checkout_expires_at: Time.at(session.fetch("expires_at")))
          else
            purchase.update!(fulfilment_state: "exception", exception_reason: "ambiguous_checkout_attempt")
          end
          return session
        end
        metadata = { purchase_id: purchase.id, user_id: purchase.user_id, course_id: purchase.course_id, attempt_key: purchase.attempt_key }
        session = @client.request(:post, "/checkout/sessions", {
          mode: "payment", client_reference_id: purchase.attempt_key,
          metadata: metadata, payment_intent_data: { metadata: metadata },
          automatic_tax: { enabled: purchase.tax_mode == "automatic" },
          adaptive_pricing: { enabled: false },
          line_items: [ { quantity: 1, price_data: { currency: purchase.currency, unit_amount: purchase.amount_minor,
            tax_behavior: purchase.tax_behavior, product_data: { name: purchase.course_title } } } ],
          success_url: "#{purchase.return_base_url}/purchases/#{purchase.id}",
          cancel_url: "#{purchase.return_base_url}/purchases/#{purchase.id}?cancelled=1"
        }, idempotency_key: purchase.attempt_key)
        purchase.update!(checkout_session_id: session.fetch("id"), checkout_url: session["url"],
          checkout_expires_at: Time.at(session.fetch("expires_at")))
        session
      end
    end
    private

    # Commit the attempt BEFORE contacting Stripe. A timeout can then be retried
    # with exactly the same parameters and key, including across worker restarts.
    def pending_purchase(user, course, settings)
      user.with_lock do
        settings.with_lock do
          Configuration.reset! # Decide on values read under the lock, not the request snapshot.
          return nil if CourseAccess.allowed?(user, course)
          raise Error, I18n.t("payments.unavailable") unless Configuration.checkout_ready?
          raise Error, "Reprice this course in the configured currency" unless course.price_currency == settings.payment_currency
          Purchase.find_by(user: user, course: course, payment_state: "pending") ||
            Purchase.create!(user: user, course: course, account_id: Configuration.secret("account_id"),
              livemode: Configuration.livemode?, course_title: course.title, amount_minor: course.price_minor,
              currency: course.price_currency, tax_mode: settings.payment_tax_mode,
              tax_behavior: settings.payment_tax_behavior, return_base_url: Configuration.base_url,
              attempt_key: SecureRandom.uuid, eligibility: { "eligible" => true, "checked_at" => Time.current.iso8601,
                "prerequisites" => course.prerequisite_course_ids })
        end
      end
    end

    def current_terms?(purchase, course, settings)
      purchase.amount_minor == course.price_minor && purchase.currency == course.price_currency &&
        purchase.tax_mode == settings.payment_tax_mode && purchase.tax_behavior == settings.payment_tax_behavior &&
        purchase.return_base_url == Configuration.base_url && same_account?(purchase)
    end

    def same_account?(purchase)
      purchase.account_id == Configuration.secret("account_id") && purchase.livemode == Configuration.livemode?
    end

    def ambiguous?(purchase)
      purchase.fulfilment_state == "exception" && purchase.exception_reason == "ambiguous_checkout_attempt"
    end

    # Makes a pending attempt unpayable, or reports :complete if the buyer already paid.
    def retire(purchase)
      purchase.with_lock do
        return :retired unless purchase.payment_state == "pending"
        # Sessions on a previous Stripe account cannot be checked or expired with the
        # current key; leave the attempt for an administrator instead of guessing.
        raise Error, I18n.t("payments.unavailable") unless same_account?(purchase)
        @client.verify_account!(purchase)
        if purchase.checkout_session_id.blank?
          # Searches every status, so a session from a timed-out create is found too.
          session = recover_session(purchase)
          return expire!(purchase) unless session
          purchase.update!(checkout_session_id: session.fetch("id"))
        end
        path = "/checkout/sessions/#{purchase.checkout_session_id}"
        session = @client.request(:get, path)
        if session["status"] == "open"
          session = begin
            @client.request(:post, "#{path}/expire")
          rescue Error
            @client.request(:get, path) # Completed between the read and the expire.
          end
        end
        session["status"] == "expired" ? expire!(purchase) : :complete
      end
    end

    def expire!(purchase)
      purchase.update!(payment_state: "expired", checkout_url: nil, fulfilment_state: "pending", exception_reason: nil)
      :retired
    end

    # The buyer paid on the older session: honour it at the terms they paid.
    def reconcile_completed(purchase)
      Reconcile.new(client: @client).call(purchase)
    rescue Error
      purchase.reload
    end

    def recover_session(purchase)
      cursor = nil
      loop do
        params = { limit: 100, created: { gte: purchase.created_at.to_i - 60, lte: purchase.created_at.to_i + 24.hours.to_i } }
        params[:starting_after] = cursor if cursor
        page = @client.request(:get, "/checkout/sessions", params)
        matches = page.fetch("data").select { |session| session["client_reference_id"] == purchase.attempt_key }
        return matches.first if matches.any?
        break unless page["has_more"]
        cursor = page.fetch("data").last.fetch("id")
      end
      nil
    end
  end
end
