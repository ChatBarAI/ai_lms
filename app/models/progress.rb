class Progress < ApplicationRecord
  self.table_name = "progresses"

  belongs_to :enrollment
  belongs_to :lesson
  has_many :quiz_attempts, dependent: :destroy

  enum :status, { not_started: 0, in_progress: 1, completed: 2 }, default: :not_started

  validates :enrollment_id, uniqueness: { scope: :lesson_id }
  validates :score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true

  scope :completed_between, ->(range) { range ? where(completed_at: range) : all }
  scope :with_score, -> { where.not(score: nil) }

  before_save :stamp_completed_at

  def next_attempt_number
    quiz_attempts.maximum(:attempt_number).to_i + 1
  end

  private

  def stamp_completed_at
    if status_changed? && completed? && completed_at.blank?
      self.completed_at = Time.current
    end
  end
end
