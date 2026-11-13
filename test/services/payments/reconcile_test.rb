require "test_helper"

class Payments::ReconcileTest < ActiveSupport::TestCase
  class FakeStripe
    attr_accessor :session, :items, :disputes, :on_request
    attr_reader :open_transactions
    def verify_account!(_purchase = nil); end
    def request(_method, path, _params = {})
      (@open_transactions ||= []) << ActiveRecord::Base.connection.open_transactions
      on_request&.call(path)
      return items if path.end_with?("/line_items")
      return disputes if path == "/disputes"
      session
    end
  end

  setup do
    @user = users(:other_student)
    @course = Course.create!(title: "Paid", owner: users(:instructor), published_at: 1.day.ago,
      access_policy: "entitlement_required", price_minor: 1000, price_currency: "eur")
    @purchase = Purchase.create!(user: @user, course: @course, account_id: "acct_test", livemode: false,
      course_title: @course.title, amount_minor: 1000, currency: "eur", tax_mode: "exempt",
      tax_behavior: "exclusive", return_base_url: "https://lms.example", attempt_key: "attempt",
      eligibility: { eligible: true }, checkout_session_id: "cs_test")
    @stripe = FakeStripe.new
    @stripe.session = {
      "id" => "cs_test", "mode" => "payment", "livemode" => false, "currency" => "eur",
      "client_reference_id" => "attempt", "status" => "complete", "payment_status" => "paid",
      "metadata" => { "purchase_id" => @purchase.id.to_s, "user_id" => @user.id.to_s, "course_id" => @course.id.to_s, "attempt_key" => "attempt" },
      "automatic_tax" => { "enabled" => false }, "amount_total" => 1000,
      "total_details" => { "amount_tax" => 0, "amount_discount" => 0, "amount_shipping" => 0 },
      "payment_intent" => { "id" => "pi_test", "status" => "succeeded", "latest_charge" => {
        "id" => "ch_test", "paid" => true, "captured" => true, "amount" => 1000, "currency" => "eur", "livemode" => false, "amount_refunded" => 0,
        "payment_method_details" => { "type" => "card" } } }
    }
    @stripe.items = { "data" => [ { "quantity" => 1, "price" => { "unit_amount" => 1000, "currency" => "eur", "tax_behavior" => "exclusive" } } ] }
    @stripe.disputes = { "data" => [] }
    @service = Payments::Reconcile.new(client: @stripe)
  end

  def reconcile
    Payments::Configuration.stub(:secret, ->(key) { key == "account_id" ? "acct_test" : "sk_test_example" }) do
      @service.call(@purchase)
    end
  end

  test "repeated fulfilment grants and enrols only once" do
    assert_difference [ "CourseEntitlement.count", "Enrollment.count", "EntitlementEvent.count" ], 1 do
      reconcile
      reconcile
    end
    assert_equal "fulfilled", @purchase.reload.fulfilment_state
  end

  test "unpaid and expired sessions never grant access" do
    @stripe.session["payment_status"] = "unpaid"
    @stripe.session["status"] = "expired"
    assert_no_difference "CourseEntitlement.count" do
      reconcile
    end
    assert_equal "expired", @purchase.reload.payment_state
  end

  test "foreign buyer amount and environment are rejected" do
    @stripe.session["metadata"]["user_id"] = users(:student).id.to_s
    assert_raises(Payments::Error) { reconcile }
    assert_nil @purchase.reload.course_entitlement
    @stripe.session["metadata"]["user_id"] = @user.id.to_s
    @stripe.session["amount_total"] = 1
    assert_raises(Payments::Error) { reconcile }
    @stripe.session["amount_total"] = 1000
    @stripe.session["livemode"] = true
    assert_raises(Payments::Error) { reconcile }
  end

  test "full refund revokes only the purchase grant and late success cannot restore it" do
    reconcile
    manual = Entitlements::Grant.call(user: @user, course: @course, source: "manual", reference: "support",
      actor: users(:admin), reason: "Support")
    @stripe.session["payment_intent"]["latest_charge"]["amount_refunded"] = 1000
    reconcile
    assert_equal "revoked", @purchase.course_entitlement.reload.status
    assert_equal "active", manual.reload.status
    assert_equal "refunded", @purchase.reload.payment_state
    @stripe.session["payment_intent"]["latest_charge"]["amount_refunded"] = 0
    reconcile
    assert_equal "revoked", @purchase.course_entitlement.reload.status
    assert_equal "refunded", @purchase.reload.payment_state
    assert Enrollment.exists?(user: @user, course: @course)
  end

  test "partial refund retains access" do
    reconcile
    @stripe.session["payment_intent"]["latest_charge"]["amount_refunded"] = 500
    reconcile
    assert_equal "active", @purchase.course_entitlement.reload.status
    assert_equal 500, @purchase.reload.refunded_minor
  end

  test "dispute suspension can be restored but explicit revocation cannot" do
    reconcile
    @stripe.disputes = { "data" => [ { "status" => "needs_response" } ] }
    reconcile
    assert_equal "suspended", @purchase.course_entitlement.reload.status
    @stripe.disputes = { "data" => [ { "status" => "won" } ] }
    reconcile
    assert_equal "active", @purchase.course_entitlement.reload.status
    Entitlements::Transition.call(grant: @purchase.course_entitlement, action: "revoke", source: "manual",
      reason: "Independent decision", actor: users(:admin), reference: "revoke")
    reconcile
    assert_equal "revoked", @purchase.course_entitlement.reload.status
  end

  test "unpublished paid course records successful payment as fulfilment exception" do
    @course.update!(published_at: nil)
    reconcile
    assert_equal "paid", @purchase.reload.payment_state
    assert_equal "course_unavailable", @purchase.exception_reason
    assert_nil @purchase.course_entitlement
  end

  test "changed prerequisites honour recorded purchase eligibility" do
    @course.prerequisite_courses << courses(:algebra)
    reconcile
    assert_equal "fulfilled", @purchase.reload.fulfilment_state
  end

  test "repricing does not mutate a purchased quote" do
    @course.update!(price_minor: 2000, title: "Renamed")
    reconcile
    assert_equal 1000, @purchase.reload.amount_minor
    assert_equal "Paid", @purchase.course_title
    assert_equal "fulfilled", @purchase.fulfilment_state
  end

  test "Stripe is never called while a database row lock is held" do
    @stripe.disputes = { "data" => [ { "status" => "lost" } ] }
    reconcile
    # Only the test's own wrapping transaction may be open during Stripe calls.
    assert_equal [ 1 ], @stripe.open_transactions.uniq
  end

  test "an older Stripe read cannot overwrite a newer reconcile" do
    reconcile
    assert_equal "paid", @purchase.reload.payment_state
    # Another worker reads Stripe after we did and records the lost dispute first.
    @stripe.on_request = lambda do |path|
      next unless path == "/disputes"
      @stripe.on_request = nil
      newer = Purchase.find(@purchase.id)
      newer.update_columns(payment_state: "lost", reconciled_at: 1.minute.from_now)
    end
    reconcile
    assert_equal "lost", @purchase.reload.payment_state
  end

  test "a payment by any method other than card is flagged and never granted" do
    @stripe.session["payment_intent"]["latest_charge"]["payment_method_details"] = { "type" => "sepa_debit" }
    assert_no_difference "CourseEntitlement.count" do
      assert_raises(Payments::Error) { reconcile }
    end
    assert_equal "exception", @purchase.reload.fulfilment_state
    assert_equal "Unsupported payment method", @purchase.exception_reason
  end
end
