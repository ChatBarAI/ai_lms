# Loads the marking queue: every lesson with unscored free-text answers, plus
# the answers themselves for lessons that must be marked by hand, so markers
# can score directly from the queue instead of digging through each report.
module MarkingWorkspace
  extend ActiveSupport::Concern

  ANSWERS_PER_LESSON = 20

  private

  def load_marking_queue(scope)
    @lesson_filter = params[:lesson].presence && scope.unscope(:select, :order).find_by(id: params[:lesson])
    scope = scope.where(id: @lesson_filter.id) if @lesson_filter
    lessons = scope.includes(:course).to_a
    @manual_lessons, @ai_lessons = lessons.partition(&:manual_marking?)

    @pending_answers = oldest_pending_answers(@manual_lessons.map(&:id))
      .preload(enrollment: :user, question: { lesson: :course })
      .order("question_answers.updated_at, question_answers.id")
      .group_by { |answer| answer.question.lesson_id }
  end

  # The oldest ANSWERS_PER_LESSON pending answers per lesson, capped in SQL so
  # a lesson with thousands of answers still loads only one batch. Marked
  # answers drop out, so the next batch moves up without pagination.
  def oldest_pending_answers(lesson_ids)
    ranked = QuestionAnswer.pending_marking
      .where(questions: { lesson_id: lesson_ids })
      .select("question_answers.id, ROW_NUMBER() OVER (PARTITION BY questions.lesson_id ORDER BY question_answers.updated_at, question_answers.id) AS position")

    QuestionAnswer.where(id: QuestionAnswer.unscoped.from(ranked, :ranked).where("ranked.position <= ?", ANSWERS_PER_LESSON).select("ranked.id"))
  end
end
