class QuestionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_course_and_lesson
  before_action :authorize_question_management!
  load_and_authorize_resource through: :lesson

  def index
    @questions = @lesson.questions
  end

  def show
  end

  def new
  end

  def create
    @question.lesson = @lesson
    @question.position ||= @lesson.questions.maximum(:position).to_i + 1
    if @question.save
      redirect_to course_lesson_questions_path(@course, @lesson), notice: "Question added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @question.update(question_params)
      redirect_to course_lesson_questions_path(@course, @lesson), notice: "Question updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @question.destroy
    redirect_to course_lesson_questions_path(@course, @lesson), notice: "Question removed.", status: :see_other
  end

  def reorder
    ids = Array(params[:ids]).map(&:to_i)
    questions = @lesson.questions.where(id: ids).index_by(&:id)
    Question.transaction do
      ids.each_with_index do |id, idx|
        questions[id]&.update_column(:position, idx + 1)
      end
    end
    head :no_content
  end

  private

  def set_course_and_lesson
    @course = Course.find_by(slug: params[:course_id]) || Course.find(params[:course_id])
    @lesson = @course.lessons.find(params[:lesson_id])
  end

  def authorize_question_management!
    # CanCanCan maps index/show to :read, which Ability grants students for
    # questions in published lessons. These management routes expose answer keys,
    # so require :manage on the parent lesson before loading any questions.
    # This limits access to the owning instructor and admins; learners take
    # quizzes through the separately authorised lesson page.
    authorize! :manage, @lesson
  end

  def question_params
    permitted = params.require(:question).permit(:prompt, :kind, :correct_answer, :points, :position, choices_list: [])
    permitted[:choices_list] ||= []
    permitted
  end
end
