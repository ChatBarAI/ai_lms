class Question < ApplicationRecord
  DEFAULT_POINTS = 1
  TRUE_FALSE_SYNONYMS = {
    "True" => %w[true t yes y correct 1],
    "False" => %w[false f no n incorrect 0]
  }.freeze

  belongs_to :lesson
  has_many :question_answers, dependent: :destroy

  enum :kind, { multiple_choice: 0, free_text: 1, true_false: 2 }, default: :multiple_choice

  attribute :points, :integer, default: DEFAULT_POINTS

  before_validation :apply_scoring_defaults

  validates :prompt, presence: true
  validates :points, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validate :correct_answer_must_match_multiple_choice, if: :multiple_choice?
  validate :correct_answer_must_be_true_or_false, if: :true_false?

  # Maps author input and learner radio values ("true", "Yes", "T", "True.")
  # to "True"/"False"; returns nil for anything else.
  def self.true_false_value(value)
    key = value.to_s.downcase.gsub(/[^a-z0-9]/, "")
    TRUE_FALSE_SYNONYMS.find { |_, words| words.include?(key) }&.first
  end

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

  # Points this question is worth when scoring; blank means DEFAULT_POINTS.
  def weight
    (points.nil? ? DEFAULT_POINTS : points).to_f
  end

  # Whether a learner's answer is correct. Free-text answers are marked by AI
  # (ai_score), so they are never correct here.
  def answer_correct?(answer_text)
    return false if free_text?

    if true_false?
      expected = self.class.true_false_value(correct_answer)
      expected.present? && expected == self.class.true_false_value(answer_text)
    else
      expected = correct_answer.to_s.strip
      expected.present? && answer_text.to_s.strip.casecmp?(expected)
    end
  end

  private

  def apply_scoring_defaults
    self.points = DEFAULT_POINTS if points.nil?
    return unless true_false?

    normalized = self.class.true_false_value(correct_answer)
    self.correct_answer = normalized if normalized
  end

  def correct_answer_must_match_multiple_choice
    return if choices_list.include?(correct_answer.to_s)

    errors.add(:correct_answer, "must exactly match one of the choices")
  end

  def correct_answer_must_be_true_or_false
    return if TRUE_FALSE_SYNONYMS.key?(correct_answer)

    errors.add(:correct_answer, "must be True or False")
  end
end
