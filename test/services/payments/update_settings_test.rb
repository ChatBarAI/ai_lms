require "test_helper"

class Payments::UpdateSettingsTest < ActiveSupport::TestCase
  class StripeConnection
    attr_accessor :account_id, :livemode, :fail
    attr_reader :requests

    def initialize(account_id: "acct_example", livemode: false)
      @account_id, @livemode = account_id, livemode
      @requests = []
    end

    def request(method, path)
      @requests << [ method, path ]
      raise Payments::Error, "Provider response must not be displayed" if fail
      path == "/account" ? { "id" => account_id } : { "livemode" => livemode }
    end
  end

  setup do
    @settings = SiteSetting.current
    @client = StripeConnection.new
    @attributes = { stripe_secret_key: "sk_test_example", stripe_webhook_secret: "whsec_example" }
  end

  def update(attributes = @attributes)
    Payments::StripeClient.stub(:new, @client) do
      Payments::UpdateSettings.new.call(@settings, attributes)
    end
  end

  test "verified credentials are encrypted at rest and take priority over deployment fallback" do
    assert update
    assert_equal [ [ :get, "/account" ], [ :get, "/balance" ] ], @client.requests
    @attributes.merge(stripe_account_id: "acct_example").each do |field, value|
      assert_equal value, @settings.reload.public_send(field)
      ciphertext = SiteSetting.connection.select_value("SELECT #{field} FROM site_settings WHERE id = #{@settings.id.to_i}")
      assert_not_includes ciphertext, value
    end
    Payments::Configuration.stub(:fallback_secret, "deployment-fallback") do
      assert_equal "sk_test_example", Payments::Configuration.secret("secret_key")
    end
  end

  test "blank credentials keep saved values without reconnecting" do
    assert update
    @client.fail = true
    assert update(stripe_secret_key: " ", stripe_webhook_secret: "", stripe_account_id: "", payment_currency: "usd")
    assert_equal "sk_test_example", @settings.reload.stripe_secret_key
    assert_equal "whsec_example", @settings.stripe_webhook_secret
    assert_equal "acct_example", @settings.stripe_account_id
    assert_equal "usd", @settings.payment_currency
  end

  test "same account key rotation is visible to later calls without restarting" do
    assert update
    assert_equal "sk_test_example", Payments::Configuration.secret("secret_key")
    assert update(stripe_secret_key: "sk_test_rotated")
    assert_equal "sk_test_rotated", Payments::Configuration.secret("secret_key")
    assert_equal "whsec_example", Payments::Configuration.secret("webhook_secret")
  end

  test "connection failure does not save credentials or other settings or expose upstream details" do
    assert update
    @client.fail = true
    assert_not update(stripe_secret_key: "sk_test_badkey", payment_currency: "usd")
    assert_not_includes @settings.errors.full_messages.join, "Provider response"
    assert_equal "sk_test_example", @settings.reload.stripe_secret_key
    assert_equal "eur", @settings.payment_currency
  end

  test "invalid account response or provider mode fails verification" do
    @client.account_id = nil
    assert_not update
    assert_nil @settings.reload.stripe_secret_key
    @client.account_id = "acct_example"
    @client.livemode = true
    assert_not update
    assert_nil @settings.reload.stripe_secret_key
  end

  test "existing inbox history prevents switching account or mode but permits rotation" do
    assert update
    PaymentEvent.create!(provider_event_id: "evt_previous", account_id: "acct_example", livemode: false,
      event_type: "checkout.session.completed", object_id: "cs_previous")
    assert update(stripe_secret_key: "sk_test_rotated")
    assert_not update(stripe_secret_key: "sk_live_example", stripe_webhook_secret: "whsec_live")
    assert_equal "sk_test_rotated", @settings.reload.stripe_secret_key
    @client.account_id = "acct_other"
    assert_not update(stripe_secret_key: "sk_test_other", stripe_webhook_secret: "whsec_other")
    assert_equal "acct_example", @settings.reload.stripe_account_id
  end

  test "identity changes require a webhook secret and reset live readiness" do
    assert update
    @settings.update!(payment_live_ready: true)
    @client.livemode = true
    assert_not update(stripe_secret_key: "sk_live_example")
    @settings.reload
    assert update(stripe_secret_key: "sk_live_example", stripe_webhook_secret: "whsec_live")
    assert_not @settings.reload.payment_live_ready?
  end

  test "empty database credentials retain environment and credentials fallback" do
    Payments::Configuration.stub(:fallback_secret, "sk_test_deployment") do
      assert_equal "sk_test_deployment", Payments::Configuration.secret("secret_key")
    end
  end
  test "purchase history also blocks replacing the account" do
    assert update
    Purchase.create!(user: users(:student), course: courses(:algebra), account_id: "acct_example", livemode: false,
      course_title: "Algebra", amount_minor: 1000, currency: "eur", tax_mode: "exempt", tax_behavior: "exclusive",
      return_base_url: "https://lms.example", attempt_key: "retained", eligibility: { eligible: true })
    @client.account_id = "acct_other"
    assert_not update(stripe_secret_key: "sk_test_other", stripe_webhook_secret: "whsec_other")
    assert_equal "acct_example", @settings.reload.stripe_account_id
  end

  test "webhook verification picks up the saved secret on the next delivery" do
    assert update
    body = { id: "evt_rotation", type: "customer.created", livemode: false }.to_json
    timestamp = Time.now.to_i
    old_digest = OpenSSL::HMAC.hexdigest("SHA256", "whsec_example", "#{timestamp}.#{body}")
    assert_nil Payments::Webhook.receive(body, "t=#{timestamp},v1=#{old_digest}")
    assert update(stripe_webhook_secret: "whsec_rotated")
    new_digest = OpenSSL::HMAC.hexdigest("SHA256", "whsec_rotated", "#{timestamp}.#{body}")
    assert_nil Payments::Webhook.receive(body, "t=#{timestamp},v1=#{new_digest}")
    assert_raises(Payments::Error) { Payments::Webhook.receive(body, "t=#{timestamp},v1=#{old_digest}") }
  end

  test "account ID is discovered without trusting supplied account attributes" do
    assert update(@attributes.merge(stripe_account_id: "acct_forged"))
    assert_equal "acct_example", @settings.reload.stripe_account_id
    assert update(stripe_account_id: "acct_forged")
    assert_equal "acct_example", @settings.reload.stripe_account_id
  end
end
