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
    attr_reader :calls, :sessions
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

  def use_session_stripe
    @client = SessionStripe.new
    @service = Payments::Checkout.new(client: @client)
  end
end
