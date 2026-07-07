class LessonQuizSubmissionService
  def initialize(lesson:, enrollment:, answers:)
    @lesson = lesson
    @enrollment = enrollment
    @answers = answers
  end

  def call
    @lesson.persist_submission_answers!(enrollment: @enrollment, answers: @answers)
    progress = @enrollment.progresses.find_or_initialize_by(lesson_id: @lesson.id)

    if pending_free_text_answers?
      return enqueue_ai_scoring!(progress) if @lesson.cbai_api_key.present?

      mark_manual_marking_pending!(progress)
    else
      score = save_immediate_score!(progress)
      { progress: progress, queued_ai_scoring: false, manual_marking_pending: false, score: score }
    end
  end

  private

  def pending_free_text_answers?
    QuestionAnswer
      .joins(:question)
      .where(enrollment_id: @enrollment.id, questions: { lesson_id: @lesson.id, kind: Question.kinds[:free_text] })
      .where(ai_score: nil)
      .exists?
  end

  def enqueue_ai_scoring!(progress)
    attempt = create_pending_attempt!(progress)
    LessonScoringJob.perform_later(progress.id, attempt.id)
    ScoringCleanupJob.set(wait: 10.minutes).perform_later(progress.id, attempt.id)

    { progress: progress, queued_ai_scoring: true, manual_marking_pending: false, score: nil }
  end

  def mark_manual_marking_pending!(progress)
    create_pending_attempt!(progress)
    { progress: progress, queued_ai_scoring: false, manual_marking_pending: true, score: nil }
  end

  def create_pending_attempt!(progress)
    submitted_at = Time.current

    progress.status = :in_progress
    progress.scoring_submitted_at = submitted_at
    progress.scoring_retry_count = 0
    progress.score = nil
    progress.save!

    progress.quiz_attempts.create!(
      enrollment: @enrollment,
      lesson: @lesson,
      attempt_number: progress.next_attempt_number,
      status: :pending,
      submitted_at: submitted_at
    )
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
