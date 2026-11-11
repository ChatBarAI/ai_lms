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
end
