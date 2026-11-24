class Admin::QuestionAnswersController < Admin::BaseController
  include AnswerScoring

  def score
    answer = QuestionAnswer.includes(question: { lesson: :course }).find(params[:id])
    lesson = answer.question.lesson
    course = lesson.course

    score_answer!(answer)
    redirect_to after_score_path(course, lesson, answer), notice: "Answer marked."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to after_score_path(course, lesson, answer), alert: e.record.errors.full_messages.to_sentence
  rescue ManualAnswerScorer::NotMarkable => e
    redirect_to after_score_path(course, lesson, answer), alert: e.message
  end

  private

  def after_score_path(course, lesson, answer)
    marking_return_path(admin_marking_queue_path, question_report_admin_course_lesson_path(course, lesson, answer.question_id)) ||
      report_admin_course_lesson_path(course, lesson)
  end
end
