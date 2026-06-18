class Question < ApplicationRecord
  belongs_to :lesson
  has_many :question_answers, dependent: :destroy

  enum :kind, { multiple_choice: 0, free_text: 1, true_false: 2 }, default: :multiple_choice

  validates :prompt, presence: true
  validates :points, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  # `choices` and `correct_answer` are stored as JSON-encoded text so the schema
  # stays portable across deployments that may not have native JSON columns.
  def choices_list
    return [] if choices.blank?
    JSON.parse(choices)
  rescue JSON::ParserError
    []
  end

  def choices_list=(arr)
    self.choices = Array(arr).to_json
  end
end
