class Admin::QuestionAnswersController < Admin::BaseController
  def score
    answer = QuestionAnswer.includes(question: { lesson: :course }, enrollment: :progresses).find(params[:id])
    score = answer_score_param

    answer.update!(ai_score: score, scored_at: Time.current)

    lesson = answer.question.lesson
    progress = answer.enrollment.progresses.find_by!(lesson_id: lesson.id)
    LessonProgressScoreService.call(progress)

    redirect_to report_admin_course_lesson_path(lesson.course, lesson), notice: "Answer marked."
  rescue ActiveRecord::RecordInvalid => e
    lesson = answer&.question&.lesson
    fallback = lesson ? report_admin_course_lesson_path(lesson.course, lesson) : admin_marking_queue_path
    redirect_to fallback, alert: e.record.errors.full_messages.to_sentence
  end

  private

  def answer_score_param
    params.require(:question_answer).permit(:ai_score).fetch(:ai_score).to_i
  end
end
