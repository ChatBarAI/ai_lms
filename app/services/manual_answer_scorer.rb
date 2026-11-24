# Records a hand-given score for one free-text answer and recalculates the
# learner's lesson progress. Instructors and admins share these rules: only
# pending free-text answers on manually marked lessons, from learners enrolled
# in the lesson's module.
#
# Raises NotMarkable when the answer breaks those rules, and
# ActiveRecord::RecordInvalid for a score outside 1..10 or when the progress
# recalculation fails. Nothing is saved in either case.
class ManualAnswerScorer
  class NotMarkable < StandardError
    def initialize(message = "This answer can't be marked manually.")
      super
    end
  end

  SCORE_FORMAT = /\A(?:[1-9]|10)\z/

  def self.call(answer, score)
    new(answer, score).call
  end

  def initialize(answer, score)
    @answer = answer
    @score = score.to_s
  end

  def call
    lesson = @answer.question.lesson
    progress = @answer.enrollment.progresses.find_by!(lesson_id: lesson.id)

    progress.with_lock do
      @answer.lock!
      raise NotMarkable unless markable?(lesson)

      unless SCORE_FORMAT.match?(@score)
        @answer.errors.add(:ai_score, "must be an integer between 1 and 10")
        raise ActiveRecord::RecordInvalid, @answer
      end

      @answer.update!(ai_score: @score.to_i, scored_at: Time.current)
      LessonProgressScoreService.call(progress)
    end
    @answer
  end

  private

  def markable?(lesson)
    @answer.question.free_text? &&
      lesson.manual_marking? &&
      @answer.ai_score.nil? &&
      @answer.enrollment.course_id == lesson.course_id
  end
end
