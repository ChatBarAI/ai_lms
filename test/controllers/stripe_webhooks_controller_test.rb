require "test_helper"

class StripeWebhooksControllerTest < ActionDispatch::IntegrationTest
  test "durable inbox survives queue submission failure" do
    event = PaymentEvent.create!(provider_event_id: "evt_test", account_id: "acct_test", livemode: false,
      event_type: "checkout.session.completed", provider_object_id: "cs_test")
    Payments::Webhook.stub(:receive, event) do
      PaymentEventJob.stub(:perform_later, ->(*) { raise IOError, "Redis unavailable" }) do
        post stripe_webhook_path, params: "{}", headers: { "CONTENT_TYPE" => "application/json" }
        assert_response :success
      end
    end
    assert_equal "pending", event.reload.state
  end

  test "invalid webhook signature is rejected" do
    Payments::Configuration.stub(:secret, "whsec_test") do
      post stripe_webhook_path, params: "{}", headers: { "CONTENT_TYPE" => "application/json", "Stripe-Signature" => "invalid" }
      assert_response :bad_request
    end
  end
end
