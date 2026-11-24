class Admin::LessonsController < Admin::BaseController
  include LearningReports
  before_action :set_course

  def index
    @lessons = @course.lessons.includes(:questions, :lesson_materials).order(:position)
  end

  def report
    load_lesson_report
  end

  def question_report
    load_question_report
  end

  private

  def set_course
    @course = Course.find_by(slug: params[:course_id]) || Course.find(params[:course_id])
  end
end
