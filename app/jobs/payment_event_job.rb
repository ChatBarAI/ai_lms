class PaymentEventJob < ApplicationJob
  queue_as :default
  retry_on Payments::Error, wait: :polynomially_longer, attempts: 8

  # No row lock is held while Stripe is called: a duplicate run is harmless because
  # the purchase update below is guarded and Reconcile is compare-and-write.
  def perform(id)
    event = PaymentEvent.find(id)
    return if event.state == "processed"
    client = Payments::StripeClient.new
    client.verify_account!
    raise Payments::Error, "Event environment mismatch" unless event.livemode == Payments::Configuration.livemode? && event.account_id == Payments::Configuration.secret("account_id")
    if event.event_type.start_with?("checkout.session.")
      session = client.request(:get, "/checkout/sessions/#{event.provider_object_id}")
      purchase = Purchase.find_by(id: session.dig("metadata", "purchase_id"), account_id: event.account_id, livemode: event.livemode)
      if purchase
        purchase.user.with_lock do
          purchase.with_lock do
            raise Payments::Error, "Checkout attempt mismatch" unless session["client_reference_id"] == purchase.attempt_key
            purchase.update!(checkout_session_id: session["id"]) if purchase.checkout_session_id.nil?
          end
        end
      end
    else
      path = if event.event_type.start_with?("charge.dispute.")
        "/disputes/#{event.provider_object_id}"
      elsif event.event_type.start_with?("refund.")
        "/refunds/#{event.provider_object_id}"
      else
        "/charges/#{event.provider_object_id}"
      end
      object = client.request(:get, path)
      intent_id = object["payment_intent"]
      intent_id ||= client.request(:get, "/charges/#{object.fetch('charge')}")["payment_intent"] if object["charge"]
      purchase = Purchase.find_by(payment_intent_id: intent_id, account_id: event.account_id, livemode: event.livemode) if intent_id
      if purchase.nil? && intent_id
        intent = client.request(:get, "/payment_intents/#{intent_id}")
        purchase = Purchase.find_by(id: intent.dig("metadata", "purchase_id"), account_id: event.account_id, livemode: event.livemode)
        raise Payments::Error, "Checkout recovery pending" if purchase && purchase.checkout_session_id.nil?
      end
    end
    Payments::Reconcile.new(client: client).call(purchase) if purchase
    event.with_lock do
      next if event.state == "processed"
      event.update!(state: "processed", processed_at: Time.current, attempts: event.attempts + 1, error_summary: nil)
    end
  rescue StandardError => e
    if event
      event.with_lock do
        # A concurrent duplicate may have finished first; never downgrade it.
        event.update!(state: "failed", attempts: event.attempts + 1, error_summary: e.class.name) unless event.state == "processed"
      end
    end
    raise
  end
end
