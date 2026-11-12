namespace :payments do
  desc "Dispatch durable payment inbox and reconcile purchases (schedule every minute)"
  task recover: :environment do
    PaymentEvent.unfinished.where("updated_at < ?", 1.minute.ago).find_each do |event|
      PaymentEventJob.perform_later(event.id)
    end
    purchases = Purchase.where(account_id: Payments::Configuration.secret("account_id"), livemode: Payments::Configuration.livemode?)
      .where.not(payment_state: %w[expired refunded lost])
    # Hourly: open attempts (sessions last at most 24h) and fulfilment exceptions.
    active = purchases.where(payment_state: "pending").where("purchases.created_at > ?", 7.days.ago)
      .or(purchases.where(fulfilment_state: "exception").where.not(payment_state: "pending"))
      .where("reconciled_at IS NULL OR reconciled_at < ?", 1.hour.ago)
    # Daily safety net for missed refund/dispute webhooks, bounded to the window in
    # which card refunds and disputes realistically occur. Refunded/lost are terminal.
    settled = purchases.where(payment_state: %w[paid disputed]).where.not(fulfilment_state: "exception")
      .where("purchases.created_at > ?", 180.days.ago)
      .where("reconciled_at IS NULL OR reconciled_at < ?", 1.day.ago)
    [ active, settled ].each do |scope|
      scope.find_each { |purchase| PurchaseReconciliationJob.perform_later(purchase.id) }
    end
    SiteSetting.current.update!(payment_recovery_at: Time.current)
    if Purchase.attention.exists? || PaymentEvent.unfinished.where("created_at < ?", 15.minutes.ago).exists?
      warn "PAYMENTS NEED ATTENTION: inspect Admin / Payments"
      exit 1
    end
  end

  desc "Remove processed event identifiers after 90 days (purchase and grant history retained)"
  task prune_events: :environment do
    PaymentEvent.where(state: "processed").where("processed_at < ?", 90.days.ago).delete_all
  end
end
