require "test_helper"

class Payments::CheckoutTest < ActiveSupport::TestCase
  class FakeStripe
    attr_reader :keys
    attr_accessor :fail_once
    def initialize
      @keys = []
    end
    def verify_account!(_purchase = nil); end
    def request(method, _path, _params = {}, idempotency_key: nil)
      @keys << idempotency_key if method == :post
      if fail_once
        self.fail_once = false
        raise Payments::Error, "Timeout"
      end
      { "id" => "cs_stable", "status" => "open", "url" => "https://checkout.stripe.com/c/pay/test", "expires_at" => 1.hour.from_now.to_i }
    end
  end

  # Tracks session state per path so retirement (lookup + expire) can be asserted.
  class SessionStripe
    attr_reader :calls, :sessions, :created_with
    def initialize
      @calls = []
      @sessions = {}
      @seq = 0
    end
    def verify_account!(_purchase = nil); end
    def request(method, path, params = {}, idempotency_key: nil)
      @calls << [ method, path ]
      case [ method, path ]
      in [ :post, "/checkout/sessions" ]
        @created_with = params
        id = "cs_#{@seq += 1}"
        @sessions[id] = { "id" => id, "status" => "open", "url" => "https://checkout.stripe.com/c/pay/#{id}",
          "expires_at" => 1.hour.from_now.to_i, "client_reference_id" => params[:client_reference_id] }
      in [ :get, "/checkout/sessions" ]
        { "data" => @sessions.values.select { |s| s["client_reference_id"] }, "has_more" => false }
      in [ :post, %r{\A/checkout/sessions/(\w+)/expire\z} ]
        id = path.split("/")[3]
        raise Payments::Error, "Stripe HTTP 400" unless @sessions[id]["status"] == "open"
        @sessions[id]["status"] = "expired"
        @sessions[id]
      in [ :get, %r{\A/checkout/sessions/(\w+)\z} ]
        @sessions.fetch(path.split("/")[3])
      end
    end
  end

  setup do
    @course = Course.create!(title: "Checkout", owner: users(:instructor), published_at: 1.day.ago,
      access_policy: "entitlement_required", price_minor: 1000, price_currency: "eur")
    SiteSetting.current.update!(payment_currency: "eur", payment_tax_mode: "exempt", app_url: "https://lms.example")
    @client = FakeStripe.new
    @service = Payments::Checkout.new(client: @client)
  end

  def checkout
    Payments::Configuration.stub(:checkout_ready?, true) do
      Payments::Configuration.stub(:secret, ->(key) { key == "account_id" ? "acct_test" : "sk_test_example" }) do
        @service.call(user: users(:other_student), course: @course)
      end
    end
  end

  test "timeout leaves durable attempt and retries same idempotency key" do
    @client.fail_once = true
    assert_difference "Purchase.count", 1 do
      assert_raises(Payments::Error) { checkout }
    end
    attempt = Purchase.last
    assert_nil attempt.checkout_session_id
    assert_no_difference "Purchase.count" do
      assert_equal attempt.id, checkout.id
      assert_equal attempt.id, checkout.id
    end
    assert_equal [ attempt.attempt_key, attempt.attempt_key ], @client.keys
  end

  test "existing grant bypasses disabled payments" do
    Entitlements::Grant.call(user: users(:other_student), course: @course, source: "manual", reference: "manual",
      actor: users(:admin), reason: "Support")
    Payments::Configuration.stub(:checkout_ready?, false) do
      assert_nil @service.call(user: users(:other_student), course: @course)
    end
    assert_empty @client.keys
  end

  test "legacy failed creation is retired before retrying with a new key" do
    @client.fail_once = true
    assert_raises(Payments::Error) { checkout }
    old = Purchase.last
    mark_legacy_request(old)
    use_session_stripe

    fresh = nil
    assert_difference "Purchase.count", 1 do
      fresh = checkout
    end
    assert_equal "expired", old.reload.payment_state
    assert_not_equal old.attempt_key, fresh.attempt_key
    assert_equal [ :get, "/checkout/sessions" ], @client.calls.first
    assert_equal [ "card" ], @client.created_with[:allowed_payment_method_types]
    assert_not @client.created_with.key?(:payment_method_types)
    assert fresh.checkout_url.present?
  end

  test "legacy creation with a lost response expires recovered session before replacement" do
    use_session_stripe
    old = checkout
    session_id = old.checkout_session_id
    old.update!(checkout_session_id: nil, checkout_url: nil)
    mark_legacy_request(old)
    @client.calls.clear

    fresh = checkout
    assert_not_equal old.attempt_key, fresh.attempt_key
    assert_equal "expired", @client.sessions[session_id]["status"]
    assert_equal "expired", old.reload.payment_state
    assert_operator @client.calls.index([ :post, "/checkout/sessions/#{session_id}/expire" ]), :<,
      @client.calls.index([ :post, "/checkout/sessions" ])
  end

  test "legacy creation already paid is recovered without a second checkout" do
    use_session_stripe
    old = checkout
    @client.sessions[old.checkout_session_id]["status"] = "complete"
    old.update!(checkout_session_id: nil, checkout_url: nil)
    mark_legacy_request(old)
    @client.calls.clear
    reconciled = []
    fake = Object.new
    fake.define_singleton_method(:call) { |purchase| reconciled << purchase.id; purchase }

    Payments::Reconcile.stub(:new, ->(**) { fake }) do
      assert_no_difference "Purchase.count" do
        assert_equal old.id, checkout.id
      end
    end
    assert_equal [ old.id ], reconciled
    assert_not_includes @client.calls, [ :post, "/checkout/sessions" ]
  end

  test "fractional minor units and unsupported currency cannot be saved" do
    @course.price_minor = "100.5"
    assert_not @course.valid?
    @course.price_minor = 100
    @course.price_currency = "zzz"
    assert_not @course.valid?
    @course.price_currency = "jpy"
    assert @course.valid?
  end

  test "repricing expires the stale session and charges the new price" do
    use_session_stripe
    first = checkout
    @course.update!(price_minor: 5000)
    second = checkout
    assert_not_equal first.id, second.id
    assert_equal "expired", first.reload.payment_state
    assert_equal "expired", @client.sessions[first.checkout_session_id]["status"]
    assert_equal 5000, second.amount_minor
    assert_equal [ "card" ], @client.created_with[:allowed_payment_method_types]
    assert_not @client.created_with.key?(:payment_method_types)
    assert_equal "open", @client.sessions[second.checkout_session_id]["status"]
  end

  test "ambiguous attempt past the idempotency window no longer blocks checkout" do
    use_session_stripe
    stuck = checkout
    stuck.update_columns(checkout_session_id: nil, checkout_url: nil, created_at: 2.days.ago,
      fulfilment_state: "exception", exception_reason: "ambiguous_checkout_attempt")
    fresh = checkout
    assert_not_equal stuck.id, fresh.id
    assert_equal "expired", stuck.reload.payment_state
    assert_equal "pending", stuck.fulfilment_state
    assert fresh.checkout_url.present?
  end

  test "stale attempt the buyer already paid is reconciled, not replaced" do
    use_session_stripe
    paid = checkout
    @client.sessions[paid.checkout_session_id]["status"] = "complete"
    @course.update!(price_minor: 5000)
    reconciled = []
    fake = Object.new
    fake.define_singleton_method(:call) { |purchase| reconciled << purchase.id; purchase }
    Payments::Reconcile.stub(:new, ->(**) { fake }) do
      assert_no_difference "Purchase.count" do
        assert_equal paid.id, checkout.id
      end
    end
    assert_equal [ paid.id ], reconciled
    assert_equal "pending", paid.reload.payment_state
  end

  private

  # Simulate an immutable snapshot written by the previous deployment.
  def mark_legacy_request(purchase)
    Purchase.where(id: purchase.id).update_all(eligibility: purchase.eligibility.except("checkout_request_version"))
    purchase.reload
  end

  def use_session_stripe
    @client = SessionStripe.new
    @service = Payments::Checkout.new(client: @client)
  end
end
