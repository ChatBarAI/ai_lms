class LessonScoringJob < ApplicationJob
  queue_as :default

  # Score all free-text QuestionAnswers for a given progress record,
  # then recalculate and save the overall lesson score.
  def perform(progress_id, quiz_attempt_id = nil)
    progress = Progress.find_by(id: progress_id)
    return unless progress

    enrollment = progress.enrollment
    lesson = progress.lesson
    api_key = lesson.cbai_api_key.presence
    return unless api_key

    client = CbaiClient.new(api_key: api_key)

    # Score each pending free-text answer sequentially
    free_text_answers = QuestionAnswer
      .joins(:question)
      .where(enrollment_id: enrollment.id, questions: { lesson_id: lesson.id, kind: Question.kinds[:free_text] })
      .where(ai_score: nil)

    free_text_answers.each do |qa|
      score = client.score_answer(
        question: qa.question.prompt,
        student_answer: qa.answer_text.to_s,
        expected_answer: qa.question.correct_answer.to_s
      )
      qa.update!(ai_score: score, scored_at: Time.current)
    rescue CbaiClient::Error => e
      Rails.logger.error "[LessonScoringJob] Failed to score answer #{qa.id}: #{e.message}"
    end

    score = recalculate_progress(progress, enrollment, lesson)
    finalize_attempt!(progress, score: score, quiz_attempt_id: quiz_attempt_id)
    ActionCable.server.broadcast("scoring:#{progress.id}", { event: "scoring_complete" })
  end

  private

  def recalculate_progress(progress, enrollment, lesson)
    questions = lesson.questions.to_a
    return nil if questions.empty?

    answers_by_question = QuestionAnswer
      .where(enrollment_id: enrollment.id, question_id: questions.map(&:id))
      .index_by(&:question_id)

    total_points = 0.0
    earned_points = 0.0

    questions.each do |q|
      weight = (q.points.presence || 1).to_f
      total_points += weight

      qa = answers_by_question[q.id]
      next unless qa

      if q.free_text?
        next if qa.ai_score.nil? # still pending — skip, score will be partial
        earned_points += (qa.ai_score / 10.0) * weight
      else
        given    = qa.answer_text.to_s.strip.downcase
        expected = q.correct_answer.to_s.strip.downcase
        earned_points += weight if expected.present? && given == expected
      end
    end

    score = total_points > 0 ? ((earned_points / total_points) * 100).round(1) : 0.0

    progress.score = score
    progress.status = score >= lesson.effective_pass_mark ? :completed : :in_progress
    progress.save!
    score
  end

  def finalize_attempt!(progress, score:, quiz_attempt_id:)
    attempt = if quiz_attempt_id.present?
      progress.quiz_attempts.find_by(id: quiz_attempt_id)
    else
      progress.quiz_attempts.pending.order(created_at: :desc).first
    end
    return unless attempt

    attempt.update!(status: :scored, score: score, completed_at: Time.current)
  end
end
