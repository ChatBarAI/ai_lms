class LessonQuizSubmissionService
  def initialize(lesson:, enrollment:, answers:)
    @lesson = lesson
    @enrollment = enrollment
    @answers = answers
  end

  def call
    questions_to_save = @lesson.persist_submission_answers!(enrollment: @enrollment, answers: @answers)
    progress = @enrollment.progresses.find_or_initialize_by(lesson_id: @lesson.id)

    if queue_ai_scoring?(questions_to_save)
      enqueue_ai_scoring!(progress)
      { progress: progress, queued_ai_scoring: true, score: nil }
    else
      score = save_immediate_score!(progress)
      { progress: progress, queued_ai_scoring: false, score: score }
    end
  end

  private

  def queue_ai_scoring?(questions_to_save)
    questions_to_save.any?(&:free_text?) && @lesson.cbai_api_key.present?
  end

  def enqueue_ai_scoring!(progress)
    submitted_at = Time.current

    progress.status = :in_progress
    progress.scoring_submitted_at = submitted_at
    progress.scoring_retry_count = 0
    progress.save!

    attempt = progress.quiz_attempts.create!(
      enrollment: @enrollment,
      lesson: @lesson,
      attempt_number: progress.next_attempt_number,
      status: :pending,
      submitted_at: submitted_at
    )

    LessonScoringJob.perform_later(progress.id, attempt.id)
    ScoringCleanupJob.set(wait: 10.minutes).perform_later(progress.id, attempt.id)
  end

  def save_immediate_score!(progress)
    score = @lesson.immediate_score_for(enrollment: @enrollment, answers: @answers)
    submitted_at = Time.current
    progress.score = score
    progress.status = score >= @lesson.effective_pass_mark ? :completed : :in_progress
    progress.save!

    progress.quiz_attempts.create!(
      enrollment: @enrollment,
      lesson: @lesson,
      attempt_number: progress.next_attempt_number,
      status: :scored,
      score: score,
      submitted_at: submitted_at,
      completed_at: submitted_at
    )

    score
  end
end
