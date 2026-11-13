class CourseEntitlement < ApplicationRecord
  belongs_to :user
  belongs_to :course
  belongs_to :purchase, optional: true
  belongs_to :granted_by, class_name: "User", optional: true
  has_many :entitlement_events, dependent: :restrict_with_error

  validates :source, inclusion: { in: %w[manual stripe] }
  validates :status, inclusion: { in: %w[active suspended revoked] }
  validates :source_reference, :starts_at, :reason, presence: true
  validates :source_reference, uniqueness: { scope: :source }
  validate do
    errors.add(:expires_at, :invalid) if expires_at && starts_at && expires_at <= starts_at
    if source == "stripe" && (!purchase || purchase.user_id != user_id || purchase.course_id != course_id)
      errors.add(:purchase, :invalid)
    end
  end
  scope :effective, -> {
    where("source <> 'stripe' OR purchase_id IN (?)", Purchase.where(account_id: Payments::Configuration.secret("account_id"),
      livemode: Payments::Configuration.livemode?).select(:id)).where(status: "active").where("starts_at <= ? AND (expires_at IS NULL OR expires_at > ?)", Time.current, Time.current)
  }
end
