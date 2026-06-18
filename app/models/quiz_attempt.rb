class QuizAttempt < ApplicationRecord
  belongs_to :progress
  belongs_to :enrollment
  belongs_to :lesson

  enum :status, { pending: 0, scored: 1 }, default: :pending

  validates :attempt_number, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :attempt_number, uniqueness: { scope: :progress_id }
  validates :score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true
  validates :submitted_at, presence: true

  scope :ordered, -> { order(:attempt_number) }
end
