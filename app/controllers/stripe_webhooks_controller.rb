# Inherits from Base to bypass application auth and SSO before_actions.
class StripeWebhooksController < ActionController::Base
  skip_before_action :verify_authenticity_token

  def create
    payload    = request.body.read
    sig_header = request.env["HTTP_STRIPE_SIGNATURE"]

    event = Stripe::Webhook.construct_event(
      payload, sig_header, Rails.configuration.stripe[:webhook_secret]
    )

    case event["type"]
    when "checkout.session.completed", "checkout.session.async_payment_succeeded"
      CoursePurchaseFulfillmentService.new(event["data"]["object"]["id"]).call
    end

    head :ok
  rescue Stripe::SignatureVerificationError
    head :bad_request
  rescue JSON::ParserError
    head :bad_request
  end
end
