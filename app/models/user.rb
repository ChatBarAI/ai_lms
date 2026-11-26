class User < ApplicationRecord
  has_many :granted_course_entitlements, class_name: "CourseEntitlement", foreign_key: :granted_by_id, dependent: :restrict_with_error
  has_many :entitlement_audit_events, class_name: "EntitlementEvent", foreign_key: :actor_id, dependent: :restrict_with_error
  has_many :purchases, dependent: :restrict_with_error
  has_many :course_entitlements, dependent: :restrict_with_error
  SUPPORTED_LOCALES = {
    "en" => "English",
    "de" => "Deutsch"
  }.freeze

  google_oauth_enabled = Rails.application.credentials.dig(:google_oauth, :client_id).present? &&
                         Rails.application.credentials.dig(:google_oauth, :client_secret).present?

  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :trackable, :lockable,
         :omniauthable, omniauth_providers: (google_oauth_enabled ? [ :google_oauth2 ] : [])

  enum :role, { student: 0, instructor: 1, admin: 2 }, default: :student

  belongs_to :organization, optional: true

  has_many :owned_courses, class_name: "Course", foreign_key: :owner_id,
           dependent: :restrict_with_error, inverse_of: :owner
  has_many :enrollments, dependent: :destroy
  has_many :courses, through: :enrollments
  has_many :progresses, through: :enrollments
  has_many :ratings, dependent: :destroy
  has_many :certificates, dependent: :destroy

  has_one_attached :avatar
  validates :avatar, content_type: %w[image/png image/jpeg image/gif image/webp],
                     size: { less_than: 5.megabytes }

  validates :time_zone, :browser_time_zone,
            inclusion: { in: ->(_) { TZInfo::Timezone.all_identifiers } }, allow_blank: true

  validates :email, presence: true
  validates :locale, presence: true, inclusion: { in: SUPPORTED_LOCALES.keys }
  validates :course_locales, presence: true
  validate :course_locales_are_supported

  # Raised when Kinde sign-in matches a local account whose email has not been
  # verified. Linking it would give the Kinde user an account whose password
  # someone else may know (account pre-hijacking).
  class UnverifiedEmailLinkError < StandardError; end

  before_validation :normalise_course_locales
  before_save :clear_email_verification, if: :email_changed_without_verification?

  scope :with_role, ->(role) { role.present? ? where(role: roles[role.to_s]) : all }
  scope :in_organization, ->(org_id) { org_id.present? ? where(organization_id: org_id) : all }
  scope :active_since, ->(time) { time.present? ? where("last_sign_in_at >= ?", time) : all }
  scope :search_term, ->(term) {
    if term.present?
      q = "%#{ActiveRecord::Base.sanitize_sql_like(term)}%"
      where("email ILIKE ? OR name ILIKE ?", q, q)
    else
      all
    end
  }

  def self.ransackable_attributes(_auth = nil)
    %w[email name role organization_id last_sign_in_at created_at]
  end

  def self.ransackable_associations(_auth = nil)
    %w[organization]
  end

  def completed_lessons_count
    progresses.where(status: Progress.statuses[:completed]).count
  end

  def average_score
    progresses.where.not(score: nil).average(:score)&.round(1)
  end

  def last_activity_at
    [ last_sign_in_at, progresses.maximum(:updated_at) ].compact.max
  end

  def mandatory_sso?
    !admin? && organization&.sso_required?
  end

  # The email of an SSO-linked account identifies that link, so users can't change it themselves.
  def sso_email_locked?
    provider.present? || mandatory_sso?
  end

  def valid_password?(password)
    !mandatory_sso? && super
  end

  # Password recovery follows the same rule as password sign-in (valid_password?):
  # only mandatory SSO blocks it. An account linked to Kinde keeps its local
  # password, so it must also be able to recover it.
  def send_reset_password_instructions
    if mandatory_sso?
      errors.add(:base, I18n.t("devise.passwords.sso_required"))
      return
    end

    super
  end

  # Completing a reset or setup link proves control of the inbox, so it also
  # verifies the email.
  def reset_password(new_password, new_password_confirmation)
    if mandatory_sso?
      errors.add(:base, I18n.t("devise.passwords.sso_required"))
      return false
    end

    self.email_verified_at ||= Time.current
    super
  end

  def email_verified?
    email_verified_at.present?
  end

  def initial_password_setup?
    persisted? && sign_in_count.to_i.zero?
  end

  def display_name
    name.presence || email
  end

  def effective_time_zone
    [ time_zone, browser_time_zone ].find { |zone| zone.present? && TZInfo::Timezone.all_identifiers.include?(zone) } || "UTC"
  end

  def locale_name
    SUPPORTED_LOCALES.fetch(locale, SUPPORTED_LOCALES.fetch(I18n.default_locale.to_s))
  end

  def course_locale_names
    course_locales.filter_map { |locale| SUPPORTED_LOCALES[locale] }
  end

  def self.from_omniauth(auth)
    user = find_or_initialize_by(provider: auth.provider, uid: auth.uid)
    user.email ||= auth.info.email
    user.name  ||= auth.info.name
    user.image_url ||= auth.info.image
    if user.new_record?
      user.password ||= Devise.friendly_token[0, 20]
      user.email_verified_at = Time.current
    end
    user.save
    user
  end

  # Used by KindeAuthController. kinde_user is a Hash with symbol keys returned by
  # client.oauth.get_user: { id:, preferred_email:, first_name:, last_name:, picture: }
  # A verified Kinde email may link an existing local account only when that
  # account's own email is verified too; existing provider links cannot be
  # overwritten through email matching.
  # Pass organization: org to auto-assign the user to an org on first sign-in.
  def self.from_kinde(kinde_user, organization: nil)
    user = find_by(provider: "kinde", uid: kinde_user[:id])
    unless user
      existing = find_by(email: kinde_user[:preferred_email])
      if existing && (kinde_user[:email_verified] != true || existing.provider.present?)
        raise ArgumentError, "Account linking requires a verified email and an unlinked account"
      end
      if existing && !existing.email_verified?
        raise UnverifiedEmailLinkError, "Existing account #{existing.id} has an unverified email"
      end
      user = existing
    end
    user ||= new

    user.provider  = "kinde"
    user.uid       = kinde_user[:id]
    user.email     = kinde_user[:preferred_email] if user.email.blank?
    user.email_verified_at ||= Time.current
    user.name      = [ kinde_user[:first_name], kinde_user[:last_name] ].compact.join(" ").presence if user.name.blank?
    user.image_url = kinde_user[:picture] if user.image_url.blank?
    user.password  = Devise.friendly_token[0, 20] if user.new_record?

    if organization
      if user.organization_id.nil?
        user.organization = organization
      elsif user.organization_id != organization.id
        Rails.logger.warn("[Kinde] User #{user.email} already belongs to org #{user.organization_id}, not reassigning to #{organization.id}")
      end
    end

    user.save
    user
  end

  private

  # A new email is unverified unless the same save verifies it (for example an
  # admin setting it, see Admin::UsersController#update).
  def email_changed_without_verification?
    persisted? && will_save_change_to_email? && !will_save_change_to_email_verified_at?
  end

  def clear_email_verification
    self.email_verified_at = nil
  end

  def normalise_course_locales
    self.course_locales = Array(course_locales).reject(&:blank?).uniq
  end

  def course_locales_are_supported
    unsupported = Array(course_locales).reject { |locale| SUPPORTED_LOCALES.key?(locale) }
    errors.add(:course_locales, "contains unsupported locales") if unsupported.any?
  end
end
