class User < ApplicationRecord
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

  has_one_attached :avatar

  validates :email, presence: true

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

  def display_name
    name.presence || email
  end

  def self.from_omniauth(auth)
    user = find_or_initialize_by(provider: auth.provider, uid: auth.uid)
    user.email ||= auth.info.email
    user.name  ||= auth.info.name
    user.image_url ||= auth.info.image
    user.password ||= Devise.friendly_token[0, 20] if user.new_record?
    user.save
    user
  end

  # Used by KindeAuthController. kinde_user is a Hash with symbol keys returned by
  # client.oauth.get_user: { id:, preferred_email:, first_name:, last_name:, picture: }
  # Falls back to email match so an existing account gets Kinde credentials attached.
  # Pass organization: org to auto-assign the user to an org on first sign-in.
  def self.from_kinde(kinde_user, organization: nil)
    user = find_by(provider: "kinde", uid: kinde_user[:id])
    user ||= find_by(email: kinde_user[:preferred_email])
    user ||= new

    user.provider  = "kinde"
    user.uid       = kinde_user[:id]
    user.email     = kinde_user[:preferred_email] if user.email.blank?
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
end
