class Lesson < ApplicationRecord
  belongs_to :course

  has_rich_text :body

  has_many :taggings, as: :taggable, dependent: :destroy
  has_many :tags, through: :taggings

  has_many :questions, -> { order(:position) }, dependent: :destroy
  has_many :ratings, dependent: :destroy
  has_many :progresses, dependent: :destroy
  has_many :question_generation_tasks, dependent: :destroy
  has_many :lesson_materials, -> { order(:position) }, dependent: :destroy

  has_one_attached :intro_video
  validates :intro_video, content_type: %w[video/mp4 video/webm video/ogg],
                          size: { less_than: 100.megabytes }

  has_one_attached :poster_image
  validates :poster_image, content_type: %w[image/png image/jpeg image/webp image/gif],
                           size: { less_than: 5.megabytes }

  has_one_attached :cover_image
  validates :cover_image, content_type: %w[image/png image/jpeg image/webp],
                          size: { less_than: 5.megabytes }

  validates :title, presence: true
  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :pass_mark, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true
  validates :duration_minutes, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :free_text_pass_level, numericality: { only_integer: true, in: 1..10 }
  validates :synthesia_api_key, length: { maximum: 255 }, allow_blank: true
  validates :heygen_api_key, length: { maximum: 255 }, allow_blank: true
  validates :anam_api_key, length: { maximum: 255 }, allow_blank: true
  validates :anam_persona_id, length: { maximum: 255 }, allow_blank: true

  def effective_pass_mark
    pass_mark.presence || SiteSetting.current.pass_mark
  end

  def public_to_guests?
    published? && course&.public_to_guests?
  end

  def required_lesson_materials
    lesson_materials.required_only
  end

  def lesson_materials_complete_for?(enrollment)
    required = required_lesson_materials
    return true if required.empty?
    return false if enrollment.blank?
    acknowledged_ids = LessonMaterialAcknowledgement.where(enrollment_id: enrollment.id, lesson_material_id: required.pluck(:id)).pluck(:lesson_material_id)
    (required.pluck(:id) - acknowledged_ids).empty?
  end

  before_validation :assign_position, on: :create

  CBAI_DISPLAY_MODES = %w[popup drawer none].freeze
  validates :cbai_display_mode, inclusion: { in: CBAI_DISPLAY_MODES }, allow_blank: true

  AI_TUTOR_PROVIDERS = %w[chatbar anam custom none].freeze
  validates :ai_tutor_provider, inclusion: { in: AI_TUTOR_PROVIDERS }, allow_blank: true
  CUSTOM_TUTOR_EMBED_TYPES = %w[iframe script].freeze
  validates :custom_tutor_embed_type, inclusion: { in: CUSTOM_TUTOR_EMBED_TYPES }, allow_blank: true
  validates :custom_tutor_embed_script, length: { maximum: 20_000 }, allow_blank: true
  validates :custom_tutor_embed_url, presence: true, if: -> {
    ai_tutor_provider_or_default == "custom" &&
      custom_tutor_embed_type_or_default == "iframe" &&
      cbai_display_mode_or_default != "none"
  }
  validates :custom_tutor_embed_script, presence: true, if: -> {
    ai_tutor_provider_or_default == "custom" &&
      custom_tutor_embed_type_or_default == "script" &&
      cbai_display_mode_or_default != "none"
  }
  validates :custom_tutor_embed_url, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[https]), message: "must be an https URL" }, allow_blank: true

  def custom_tutor_embed_type_or_default
    CUSTOM_TUTOR_EMBED_TYPES.include?(custom_tutor_embed_type) ? custom_tutor_embed_type : "iframe"
  end

  def cbai_display_mode_or_default
    CBAI_DISPLAY_MODES.include?(cbai_display_mode) ? cbai_display_mode : "popup"
  end

  def ai_tutor_provider_or_default
    AI_TUTOR_PROVIDERS.include?(ai_tutor_provider) ? ai_tutor_provider : "chatbar"
  end

  QUIZ_LAYOUTS = %w[scrolling one_at_a_time].freeze
  validates :quiz_layout, inclusion: { in: QUIZ_LAYOUTS }

  def quiz_layout_or_default
    QUIZ_LAYOUTS.include?(quiz_layout) ? quiz_layout : "scrolling"
  end

  def cbai_enabled?
    ai_tutor_provider_or_default == "chatbar" &&
      cbai_token.present? &&
      cbai_display_mode_or_default != "none"
  end

  def custom_tutor_enabled?
    return false unless ai_tutor_provider_or_default == "custom"
    return false if cbai_display_mode_or_default == "none"

    if custom_tutor_embed_type_or_default == "script"
      custom_tutor_embed_script.present?
    else
      custom_tutor_embed_url.present?
    end
  end

  def anam_enabled?
    ai_tutor_provider_or_default == "anam" &&
      anam_api_key.present? &&
      anam_persona_id.present? &&
      cbai_display_mode_or_default != "none"
  end

  scope :published, -> { where(published_at: ..Time.current) }

  def published?
    published_at.present? && published_at <= Time.current
  end

  def average_rating
    ratings.average(:stars)&.round(2)
  end

  def attempts_count
    progresses.count
  end

  def completions_count
    progresses.where(status: Progress.statuses[:completed]).count
  end

  def average_score
    progresses.where.not(score: nil).average(:score)&.round(1)
  end

  def pass_rate
    threshold = effective_pass_mark
    scored = progresses.where.not(score: nil)
    total = scored.count
    return 0 if total.zero?
    ((scored.where("score >= ?", threshold).count.to_f / total) * 100).round(1)
  end

  # Returns the subset of questions the student still needs to redo.
  # For multiple-choice/true-false: wrong if answer_text != correct_answer.
  # For free-text: wrong if ai_score is nil (pending) or below free_text_pass_level.
  # Returns all questions when enrollment is blank or has no prior answers.
  def incorrect_questions_for(enrollment)
    all_qs = questions.to_a
    return all_qs if enrollment.blank? || all_qs.empty?

    answers_by_question = QuestionAnswer
      .where(enrollment_id: enrollment.id, question_id: all_qs.map(&:id))
      .index_by(&:question_id)

    return all_qs if answers_by_question.empty?

    all_qs.select do |q|
      qa = answers_by_question[q.id]
      next true if qa.nil?

      if q.free_text?
        qa.ai_score.nil? || qa.ai_score < free_text_pass_level
      else
        qa.answer_text.to_s.strip.downcase != q.correct_answer.to_s.strip.downcase
      end
    end
  end

  # In retry mode only save submitted questions so previous correct answers
  # remain untouched; otherwise save all lesson questions.
  def questions_for_submission(submitted_answer_ids:)
    return questions unless retry_incorrect_only? && submitted_answer_ids.any?

    questions.where(id: submitted_answer_ids)
  end

  def persist_submission_answers!(enrollment:, answers:)
    answer_map = answers.to_h.transform_keys(&:to_s)
    submitted_ids = answer_map.keys.map(&:to_i)
    questions_to_save = questions_for_submission(submitted_answer_ids: submitted_ids).to_a

    questions_to_save.each do |question|
      qa = QuestionAnswer.find_or_initialize_by(enrollment_id: enrollment.id, question_id: question.id)
      qa.answer_text = answer_map[question.id.to_s].to_s.strip
      qa.ai_score = nil
      qa.scored_at = nil
      qa.save!
    end

    questions_to_save
  end

  def immediate_score_for(enrollment:, answers:)
    answer_map = answers.to_h.transform_keys(&:to_s)
    all_questions = questions.to_a
    return 0.0 if all_questions.empty?

    stored_answers = if retry_incorrect_only?
      QuestionAnswer
        .where(enrollment_id: enrollment.id, question_id: all_questions.map(&:id))
        .index_by { |qa| qa.question_id.to_s }
    else
      {}
    end

    total_points = 0.0
    earned_points = 0.0

    all_questions.each do |question|
      weight = (question.points.presence || 1).to_f
      total_points += weight
      given = if answer_map.key?(question.id.to_s)
        answer_map[question.id.to_s].to_s.strip.downcase
      else
        stored_answers[question.id.to_s]&.answer_text.to_s.strip.downcase
      end
      expected = question.correct_answer.to_s.strip.downcase
      earned_points += weight if expected.present? && given == expected
    end

    total_points.positive? ? ((earned_points / total_points) * 100).round(1) : 0.0
  end

  private

  def assign_position
    return unless position.blank? && course.present?

    self.position = course.lessons.maximum(:position).to_i + 1
  end
end
