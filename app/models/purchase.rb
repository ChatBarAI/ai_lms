class Purchase < ApplicationRecord
  belongs_to :user
  belongs_to :course
  has_one :course_entitlement, dependent: :restrict_with_error
  attr_readonly :user_id, :course_id, :provider, :account_id, :livemode, :course_title,
    :amount_minor, :currency, :tax_mode, :tax_behavior, :eligibility, :attempt_key, :return_base_url
  validates :amount_minor, numericality: { only_integer: true, greater_than: 0 }
  validates :attempt_key, :course_title, :account_id, :currency, presence: true
  validates :payment_state, inclusion: { in: %w[pending paid expired refunded disputed lost] }
  validates :fulfilment_state, inclusion: { in: %w[pending fulfilled exception] }
  scope :attention, -> { where(fulfilment_state: "exception") }
end
