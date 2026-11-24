class QuestionAnswersController < ApplicationController
  include AnswerScoring
  before_action :authenticate_user!

  def score
    course = Course.find_by(slug: params[:course_id]) || Course.find(params[:course_id])
    authorize! :report, course
    lesson = course.lessons.find(params[:lesson_id])
    answer = QuestionAnswer.joins(:question).where(questions: { lesson_id: lesson.id }).find(params[:id])
    authorize! :score, answer
    score_answer!(answer)

    redirect_to after_score_path(course, lesson, answer), notice: "Answer marked."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to after_score_path(course, lesson, answer), alert: e.record.errors.full_messages.to_sentence
  rescue ManualAnswerScorer::NotMarkable => e
    redirect_to root_path, alert: e.message
  end

  private

  def after_score_path(course, lesson, answer)
    marking_return_path(marking_queue_path, question_report_course_lesson_path(course, lesson, answer.question_id)) ||
      report_course_lesson_path(course, lesson)
  end
end
