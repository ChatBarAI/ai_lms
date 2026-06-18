class LessonMaterialsController < ApplicationController
  before_action :authenticate_user!, except: [ :index, :show ]
  before_action :set_course_and_lesson
  load_and_authorize_resource through: :lesson
  skip_authorize_resource only: [ :acknowledge, :reorder ]

  def index
    @lesson_materials = @lesson.lesson_materials
  end

  def show
  end

  def new
  end

  def create
    @lesson_material.lesson = @lesson
    if @lesson_material.save
      redirect_to edit_course_lesson_path(@course, @lesson), notice: "Material added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @lesson_material.update(lesson_material_params)
      redirect_to edit_course_lesson_path(@course, @lesson), notice: "Material updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @lesson_material.destroy
    redirect_to edit_course_lesson_path(@course, @lesson), notice: "Material removed.", status: :see_other
  end

  def reorder
    authorize! :manage, @lesson
    ids = Array(params[:ids]).map(&:to_i)
    materials = @lesson.lesson_materials.where(id: ids).index_by(&:id)
    LessonMaterial.transaction do
      ids.each_with_index do |id, idx|
        materials[id]&.update_column(:position, idx + 1)
      end
    end
    head :no_content
  end

  def acknowledge
    enrollment = current_user&.enrollments&.find_by(course_id: @course.id)
    unless enrollment
      redirect_to course_lesson_path(@course, @lesson), alert: "Enrol to mark materials as complete." and return
    end

    ack = LessonMaterialAcknowledgement.new(lesson_material_id: @lesson_material.id, enrollment_id: enrollment.id)
    authorize! :create, ack
    ack.save
    redirect_to course_lesson_path(@course, @lesson, anchor: "material-#{@lesson_material.id}"),
                notice: "Marked as complete."
  end

  private

  def set_course_and_lesson
    @course = Course.find_by(slug: params[:course_id]) || Course.find(params[:course_id])
    @lesson = @course.lessons.find(params[:lesson_id])
  end

  def lesson_material_params
    params.require(:lesson_material).permit(:title, :kind, :position, :required, :body, :document, :raw_html_content, :audio_file, :url, :image_file)
  end
end
