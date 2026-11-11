require "test_helper"

class Payments::WebhookTest < ActiveSupport::TestCase
  def configuration(key)
    { "webhook_secret" => "whsec_test", "secret_key" => "sk_test_test", "account_id" => "acct_test" }[key]
  end

  def payload(**overrides)
    { id: "evt_test", type: "checkout.session.completed", livemode: false,
      data: { object: { id: "cs_test", customer_details: { email: "private@example.com" } } } }.merge(overrides).to_json
  end

  def signature(body, timestamp = Time.now.to_i)
    digest = OpenSSL::HMAC.hexdigest("SHA256", "whsec_test", "#{timestamp}.#{body}")
    "t=#{timestamp},v1=#{digest}"
  end

  test "verified events are durably deduplicated without retaining customer details" do
    Payments::Configuration.stub(:secret, method(:configuration)) do
      body = payload
      assert_difference "PaymentEvent.count", 1 do
        2.times { Payments::Webhook.receive(body, signature(body)) }
      end
      assert_not_includes PaymentEvent.last.attributes.to_json, "private@example.com"
    end
  end

  test "forged stale and foreign environment events fail" do
    Payments::Configuration.stub(:secret, method(:configuration)) do
      body = payload
      assert_raises(Payments::Error) { Payments::Webhook.receive(body + " ", signature(body)) }
      assert_raises(Payments::Error) { Payments::Webhook.receive(body, signature(body, 10.minutes.ago.to_i)) }
      body = payload(livemode: true)
      assert_raises(Payments::Error) { Payments::Webhook.receive(body, signature(body)) }
      body = payload(account: "acct_foreign")
      assert_raises(Payments::Error) { Payments::Webhook.receive(body, signature(body)) }
    end
  end

  test "unsupported events are acknowledged without creating work" do
    Payments::Configuration.stub(:secret, method(:configuration)) do
      body = payload(type: "customer.created")
      assert_nil Payments::Webhook.receive(body, signature(body))
    end
  end
end
