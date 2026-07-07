class LessonProgressScoreService
  def self.call(progress, attempt: nil)
    new(progress, attempt: attempt).call
  end

  def initialize(progress, attempt: nil)
    @progress = progress
    @attempt = attempt
    @enrollment = progress.enrollment
    @lesson = progress.lesson
  end

  def call
    return nil if pending_free_text_answers?

    score = calculate_score
    @progress.score = score
    @progress.status = score >= @lesson.effective_pass_mark ? :completed : :in_progress
    @progress.save!
    finalize_attempt(score)
    score
  end

  private

  def pending_free_text_answers?
    QuestionAnswer
      .joins(:question)
      .where(enrollment_id: @enrollment.id, questions: { lesson_id: @lesson.id, kind: Question.kinds[:free_text] })
      .where(ai_score: nil)
      .exists?
  end

  def calculate_score
    questions = @lesson.questions.to_a
    return 0.0 if questions.empty?

    answers_by_question = QuestionAnswer
      .where(enrollment_id: @enrollment.id, question_id: questions.map(&:id))
      .index_by(&:question_id)

    total_points = 0.0
    earned_points = 0.0

    questions.each do |question|
      weight = (question.points.presence || 1).to_f
      total_points += weight

      answer = answers_by_question[question.id]
      next unless answer

      if question.free_text?
        earned_points += (answer.ai_score / 10.0) * weight
      else
        given = answer.answer_text.to_s.strip.downcase
        expected = question.correct_answer.to_s.strip.downcase
        earned_points += weight if expected.present? && given == expected
      end
    end

    total_points.positive? ? ((earned_points / total_points) * 100).round(1) : 0.0
  end

  def finalize_attempt(score)
    attempt = @attempt || @progress.quiz_attempts.pending.order(created_at: :desc).first
    return unless attempt

    attempt.update!(status: :scored, score: score, completed_at: Time.current)
  end
end
