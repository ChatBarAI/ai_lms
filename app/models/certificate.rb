class Certificate < ApplicationRecord
  belongs_to :user
  belongs_to :course

  validates :token, presence: true, uniqueness: true
  validates :issued_at, presence: true
  validates :user_id, uniqueness: { scope: :course_id, message: "already has a certificate for this course" }

  before_validation :set_issued_at, on: :create
  before_validation :generate_token, on: :create

  def self.ransackable_attributes(auth_object = nil)
    %w[course_id created_at id issued_at token updated_at user_id]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[user course]
  end

  # Find an existing certificate or issue a new one. Idempotent.
  def self.find_or_issue(user:, course:)
    find_or_create_by!(user: user, course: course)
  end

  private

  def set_issued_at
    self.issued_at ||= Time.current
  end

  def generate_token
    return if token.present?
    self.token = loop do
      candidate = SecureRandom.urlsafe_base64(16)
      break candidate unless self.class.exists?(token: candidate)
    end
  end
end
