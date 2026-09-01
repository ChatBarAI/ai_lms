class Enrollment < ApplicationRecord
  belongs_to :user
  belongs_to :course

  has_many :progresses, dependent: :destroy
  has_many :lesson_material_acknowledgements, dependent: :destroy
  has_many :question_answers, dependent: :destroy

  enum :role, { student: 0, instructor: 1, assistant: 2 }, default: :student

  validates :user_id, uniqueness: { scope: :course_id }

  before_validation :set_enrolled_at, on: :create

  scope :enrolled_between, ->(range) { range ? where(enrolled_at: range) : all }
  scope :completed, lambda {
    required_lessons = Lesson.required_for_completion.where("lessons.course_id = enrollments.course_id")
    completed_lesson_ids = Progress.completed
      .where("progresses.enrollment_id = enrollments.id")
      .select(:lesson_id)
    incomplete_required_lessons = required_lessons.where.not(id: completed_lesson_ids)

    where(required_lessons.arel.exists)
      .where.not(incomplete_required_lessons.arel.exists)
  }
  scope :active, -> { joins(:progresses).where(progresses: { status: [ Progress.statuses[:in_progress], Progress.statuses[:completed] ] }).distinct }

  def completion_percentage
    total = lessons_required_count
    return 0 if total.zero?
    ((lessons_completed_count.to_f / total) * 100).round(1)
  end

  def lessons_required_count
    course.lessons_required_for_completion.count
  end

  def lessons_completed_count
    completed_required_progresses.count
  end

  def average_score
    progresses.where.not(score: nil).average(:score)&.round(1)
  end

  def last_progress_at
    progresses.maximum(:updated_at)
  end

  def fully_completed?
    total = lessons_required_count
    total.positive? && lessons_completed_count >= total
  end

  private

  def completed_required_progresses
    progresses.completed.where(lesson_id: course.lessons_required_for_completion.select(:id))
  end

  def set_enrolled_at
    self.enrolled_at ||= Time.current
  end
end
