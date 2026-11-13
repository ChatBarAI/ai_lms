class PaymentEvent < ApplicationRecord
  validates :provider_event_id, :account_id, :event_type, :provider_object_id, presence: true
  scope :unfinished, -> { where(state: %w[pending failed]) }
end
