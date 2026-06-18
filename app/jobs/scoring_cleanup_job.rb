class ScoringCleanupJob < ApplicationJob
  queue_as :default

  MAX_RETRIES = 2
  # A job is considered stuck if scoring_submitted_at is older than this.
  STUCK_AFTER = 8.minutes

  def perform(progress_id, quiz_attempt_id = nil)
    progress = Progress.find_by(id: progress_id)
    return unless progress

    enrollment = progress.enrollment
    lesson     = progress.lesson

    pending_count = QuestionAnswer
      .joins(:question)
      .where(enrollment_id: enrollment.id,
             questions: { lesson_id: lesson.id, kind: Question.kinds[:free_text] })
      .where(ai_score: nil)
      .count

    # Scoring already completed — nothing to do.
    return if pending_count.zero?

    # Submitted recently — wait for the original job to finish.
    # If scoring_submitted_at is nil the record is legacy-stuck; treat as overdue.
    return if progress.scoring_submitted_at.present? && progress.scoring_submitted_at > STUCK_AFTER.ago

    if progress.scoring_retry_count < MAX_RETRIES
      attempt = progress.scoring_retry_count + 1
      progress.scoring_retry_count = attempt
      progress.scoring_submitted_at = Time.current
      progress.save!

      Rails.logger.warn(
        "[ScoringCleanupJob] Progress #{progress_id} stuck " \
        "(#{pending_count} pending answers) — retry ##{attempt}/#{MAX_RETRIES}"
      )

      LessonScoringJob.perform_later(progress_id, quiz_attempt_id)
      ScoringCleanupJob.set(wait: 10.minutes).perform_later(progress_id, quiz_attempt_id)
    else
      Rails.logger.error(
        "[ScoringCleanupJob] Progress #{progress_id} stuck after #{MAX_RETRIES} retries " \
        "(#{pending_count} pending answers) — failing to 0 and broadcasting completion"
      )

      QuestionAnswer
        .joins(:question)
        .where(enrollment_id: enrollment.id,
               questions: { lesson_id: lesson.id, kind: Question.kinds[:free_text] })
        .where(ai_score: nil)
        .update_all(ai_score: 0, scored_at: Time.current)

      # Recalculate and broadcast via the scoring job (no pending answers remain).
      LessonScoringJob.perform_now(progress_id, quiz_attempt_id)
    end
  end
end
