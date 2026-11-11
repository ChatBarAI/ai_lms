namespace :payments do
  desc "Dispatch durable payment inbox and reconcile purchases (schedule every minute)"
  task recover: :environment do
    PaymentEvent.unfinished.where("updated_at < ?", 1.minute.ago).find_each do |event|
      PaymentEventJob.perform_later(event.id)
    end
    Purchase.where(account_id: Payments::Configuration.secret("account_id"), livemode: Payments::Configuration.livemode?)
      .where.not(payment_state: "expired")
      .where("reconciled_at IS NULL OR reconciled_at < ?", 1.hour.ago).find_each do |purchase|
        PurchaseReconciliationJob.perform_later(purchase.id)
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
