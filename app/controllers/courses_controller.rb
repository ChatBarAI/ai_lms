class CoursesController < ApplicationController
  before_action :authenticate_user!, only: [ :new, :create, :edit, :update, :destroy, :certificate_layout, :update_certificate_layout ]
  load_and_authorize_resource find_by: :slug

  def index
    @courses = (params[:mine] && current_user ? current_user.owned_courses : Course.published).includes(:tags).order(published_at: :desc)
  end

  def show
    @enrollment = current_user&.enrollments&.find_by(course_id: @course.id)
    visible_lessons = can?(:update, @course) ? @course.lessons : @course.lessons.published
    @lessons = visible_lessons.includes(:tags)

    @queued_for_marking_lesson_ids = if @enrollment
      QuestionAnswer
        .joins(:question)
        .where(enrollment_id: @enrollment.id, questions: { lesson_id: visible_lessons.select(:id), kind: Question.kinds[:free_text] })
        .where(ai_score: nil)
        .distinct
        .pluck("questions.lesson_id")
    else
      []
    end
  end

  def new
  end

  def create
    @course.owner = current_user
    if @course.save
      redirect_to @course, notice: "Course created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @lessons = @course.lessons.order(:position)
  end

  def update
    bool = ActiveModel::Type::Boolean.new
    @course.cover_image.purge if bool.cast(params.dig(:course, :remove_cover_image))
    @course.certificate_template.purge if bool.cast(params.dig(:course, :remove_certificate_template))
    if @course.update(course_params)
      redirect_to @course, notice: "Course updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def certificate_layout
    @layout = @course.certificate_layout_with_defaults
  end

  def update_certificate_layout
    if params[:reset].present?
      @course.update!(certificate_layout: {})
      redirect_to certificate_layout_course_path(@course), notice: "Layout reset to defaults." and return
    end

    layout = (params[:layout] || {}).to_unsafe_h.slice(*Course::CERTIFICATE_FIELDS)
    cleaned = layout.each_with_object({}) do |(key, attrs), h|
      h[key] = {
        "x"     => attrs["x"].to_f.clamp(0, 100),
        "y"     => attrs["y"].to_f.clamp(0, 100),
        "size"  => attrs["size"].to_f.clamp(6, 120),
        "align" => %w[left center right].include?(attrs["align"]) ? attrs["align"] : "center",
        "bold"  => ActiveModel::Type::Boolean.new.cast(attrs["bold"]) || false
      }
    end

    if @course.update(certificate_layout: cleaned)
      redirect_to certificate_layout_course_path(@course), notice: "Certificate layout saved."
    else
      @layout = @course.certificate_layout_with_defaults
      render :certificate_layout, status: :unprocessable_entity
    end
  end

  def destroy
    @course.destroy
    redirect_to courses_path, notice: "Course deleted.", status: :see_other
  end

  def publish
    @course.update(published_at: Time.current)
    redirect_to @course, notice: "Course published."
  end

  def unpublish
    @course.update(published_at: nil)
    redirect_to @course, notice: "Course unpublished."
  end

  private

  def course_params
    params.require(:course).permit(:title, :description, :subject_id, :published_at, :cover_image, :certificate_template, tag_ids: [])
  end
end
