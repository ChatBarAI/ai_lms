# No browser session, SSO, locale callbacks or CSRF exemptions elsewhere.
class StripeWebhooksController < ActionController::Base
  skip_forgery_protection

  def create
    return head :payload_too_large if request.content_length.to_i > 1.megabyte
    body = request.body.read(1.megabyte + 1)
    return head :payload_too_large if body.bytesize > 1.megabyte
    event = Payments::Webhook.receive(body, request.headers["Stripe-Signature"])
    if event && event.state != "processed"
      begin
        PaymentEventJob.perform_later(event.id)
      rescue StandardError
        Rails.logger.error("Payment inbox persisted; recovery dispatcher must enqueue event #{event.id}")
      end
    end
    head :ok
  rescue Payments::Error
    head :bad_request
  end
end
