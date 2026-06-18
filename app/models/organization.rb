class Organization < ApplicationRecord
  has_many :users, dependent: :nullify

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :slug, presence: true, uniqueness: true,
                   format: { with: /\A[a-z0-9-]+\z/ }
  validates :contact_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :kinde_connection_id, uniqueness: true, allow_nil: true
  validates :kinde_connection_provider, inclusion: { in: %w[microsoft google other] }, allow_nil: true
  validates :sso_domain, format: { with: /\A[a-z0-9.-]+\z/i }, allow_nil: true
  validates :sso_domain, uniqueness: { case_sensitive: false }, allow_nil: true
  validate :sso_required_needs_connection

  before_validation :assign_slug
  before_validation :normalise_sso_fields

  scope :by_name, -> { order(:name) }

  def to_param
    slug.presence || id.to_s
  end

  def sso_configured?
    kinde_connection_id.present?
  end

  # Returns the org whose sso_domain matches the given email domain, or nil.
  def self.for_email_domain(email)
    domain = email.to_s.split("@").last&.downcase
    return nil if domain.blank?
    find_by(sso_domain: domain)
  end

  def sso_login_url(base_url)
    "#{base_url}/auth/org/#{slug}"
  end

  def self.ransackable_attributes(_auth = nil)
    %w[id name slug]
  end

  def self.ransackable_associations(_auth = nil)
    %w[users]
  end

  def users_count
    users.count
  end

  def enrollments
    Enrollment.where(user_id: users.select(:id))
  end

  def progresses
    Progress.where(enrollment_id: enrollments.select(:id))
  end

  def completion_rate
    total = progresses.count
    return 0 if total.zero?
    ((progresses.where(status: Progress.statuses[:completed]).count.to_f / total) * 100).round(1)
  end

  private

  def assign_slug
    self.slug = slug.presence || name.to_s.parameterize
  end

  def normalise_sso_fields
    self.kinde_connection_id = kinde_connection_id.presence
    self.sso_domain = sso_domain.to_s.downcase.presence
  end

  def sso_required_needs_connection
    if sso_required? && !sso_configured?
      errors.add(:sso_required, "cannot be enabled without a Kinde connection ID")
    end
  end
end
