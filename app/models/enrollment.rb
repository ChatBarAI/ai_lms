class Enrollment < ApplicationRecord
  belongs_to :user
  belongs_to :course

  has_many :progresses, dependent: :destroy
  has_many :lesson_material_acknowledgements, dependent: :destroy
  has_many :question_answers, dependent: :destroy

  enum :role, { student: 0, tutor: 1, assistant: 2 }, default: :student

  attr_accessor :skip_prerequisite_check

  validates :user_id, uniqueness: { scope: :course_id }
  validate :prerequisites_must_be_met, on: :create

  before_validation :set_enrolled_at, on: :create

  scope :enrolled_between, ->(range) { range ? where(enrolled_at: range) : all }
  scope :completed, lambda {
    joins(:progresses).where(progresses: { status: Progress.statuses[:completed] })
      .group("enrollments.id")
      .having("COUNT(progresses.id) >= (SELECT COUNT(*) FROM lessons WHERE lessons.course_id = enrollments.course_id)")
  }
  scope :active, -> { joins(:progresses).where(progresses: { status: [ Progress.statuses[:in_progress], Progress.statuses[:completed] ] }).distinct }

  def completion_percentage
    total = course.lessons.count
    return 0 if total.zero?
    completed = progresses.where(status: Progress.statuses[:completed]).count
    ((completed.to_f / total) * 100).round(1)
  end

  def lessons_completed_count
    progresses.where(status: Progress.statuses[:completed]).count
  end

  def average_score
    progresses.where.not(score: nil).average(:score)&.round(1)
  end

  def last_progress_at
    progresses.maximum(:updated_at)
  end

  def fully_completed?
    total = course.lessons.count
    total.positive? && lessons_completed_count >= total
  end

  private

  def set_enrolled_at
    self.enrolled_at ||= Time.current
  end

  def prerequisites_must_be_met
    return if skip_prerequisite_check
    return if course.blank? || user.blank?

    missing = course.missing_prerequisites_for(user)
    return if missing.empty?

    errors.add(:base, "Complete these courses first: #{missing.map(&:title).to_sentence}")
  end
end
