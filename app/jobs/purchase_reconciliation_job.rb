class PurchaseReconciliationJob < ApplicationJob
  queue_as :default
  retry_on Payments::Error, wait: :polynomially_longer, attempts: 5

  def perform(id)
    purchase = Purchase.find(id)
    Payments::Checkout.new.ensure_session(purchase) if purchase.checkout_session_id.nil?
    Payments::Reconcile.new.call(purchase) if purchase.reload.checkout_session_id
  rescue StandardError => e
    purchase&.update!(fulfilment_state: "exception", exception_reason: e.class.name)
    raise
  end
end
