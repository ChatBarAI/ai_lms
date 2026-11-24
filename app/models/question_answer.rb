class QuestionAnswer < ApplicationRecord
  belongs_to :enrollment
  belongs_to :question

  validates :enrollment_id, uniqueness: { scope: :question_id }
  validates :ai_score, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 10 }, allow_nil: true

  scope :scored, -> { where.not(ai_score: nil) }
  scope :pending, -> { where(ai_score: nil) }
  scope :free_text, -> { joins(:question).merge(Question.free_text) }
  scope :passing, ->(level) { where(ai_score: level..) }
  scope :failing, ->(level) { where(ai_score: ...level) }

  # Answers from learners enrolled in the module the lesson belongs to. An
  # answer left behind by a learner who is no longer enrolled has no progress
  # to update, so it cannot be marked and must not be counted.
  scope :from_course_learners, -> {
    joins(:enrollment, question: :lesson).where("enrollments.course_id = lessons.course_id")
  }

  # Free-text answers waiting for a score: the single definition behind the
  # marking queue, nav badge, alerts and report counts. Questions and lessons
  # are joined, so callers can filter on either.
  scope :pending_marking, -> { free_text.pending.from_course_learners }

  MARKING_STAT_KEYS = %i[total scored pending passed failed average].freeze

  # Totals for the current scope in one query:
  # { total:, scored:, pending:, passed:, failed:, average: }
  def self.marking_stats(pass_level)
    MARKING_STAT_KEYS.zip(pick(*marking_stat_columns(pass_level))).to_h
  end

  # The same totals per question: { question_id => { total:, ... } }
  def self.marking_stats_by_question(pass_level)
    group(:question_id)
      .pluck(:question_id, *marking_stat_columns(pass_level))
      .to_h { |question_id, *values| [ question_id, MARKING_STAT_KEYS.zip(values).to_h ] }
  end

  def self.marking_stat_columns(pass_level)
    [
      "COUNT(*)",
      "COUNT(question_answers.ai_score)",
      "COUNT(*) FILTER (WHERE question_answers.ai_score IS NULL)",
      sanitize_sql_array([ "COUNT(*) FILTER (WHERE question_answers.ai_score >= ?)", pass_level ]),
      sanitize_sql_array([ "COUNT(*) FILTER (WHERE question_answers.ai_score < ?)", pass_level ]),
      "AVG(question_answers.ai_score)"
    ].map { |sql| Arel.sql(sql) }
  end
  private_class_method :marking_stat_columns
end
