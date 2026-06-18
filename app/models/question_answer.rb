class QuestionAnswer < ApplicationRecord
  belongs_to :enrollment
  belongs_to :question

  validates :enrollment_id, uniqueness: { scope: :question_id }
  validates :ai_score, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 10 }, allow_nil: true

  scope :scored, -> { where.not(ai_score: nil) }
  scope :pending_ai, -> { where(ai_score: nil) }
end
