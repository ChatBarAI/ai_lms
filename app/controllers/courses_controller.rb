class CoursesController < ApplicationController
  include LearningReports
  include LessonGating
  before_action :authenticate_user!, only: [ :report, :new, :create, :edit, :update, :destroy, :certificate_layout, :update_certificate_layout ]
  load_and_authorize_resource find_by: :slug

  def index
    @sort = params[:sort] == "learning_order" ? "learning_order" : "published_at"
    scope = params[:mine] && current_user ? current_user.owned_courses : Course.catalog_visible_to(current_user)
    @courses = scope.includes(:tags, :prerequisite_courses).merge(Course.catalog_order(@sort))
  end

  def show
    @enrollment = current_enrollment
    visible_lessons = can?(:update, @course) ? @course.lessons : @course.lessons.published
    @lessons = visible_lessons.includes(:tags)
    @queued_for_marking_lesson_ids = @enrollment ? @enrollment.lesson_ids_awaiting_marking : Set.new
    @locked_lessons = viewer_locked_lessons

    if can?(:report, @course)
      @pending_marking_count = QuestionAnswer.pending_marking.merge(Lesson.manually_marked)
        .where(lessons: { course_id: @course.id }).count
    end
  end

  def report
    load_course_report
    render "admin/courses/report"
  end

  def new
  end

  def create
    @course.owner = current_user
    if @course.save
      redirect_to @course, notice: t("courses.flash.created", **helpers.terms)
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
      redirect_to @course, notice: t("courses.flash.updated", **helpers.terms)
    else
      @lessons = @course.lessons.order(:position)
      render :edit, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordInvalid => e
    @course.errors.merge!(e.record.errors)
    @lessons = @course.lessons.order(:position)
    render :edit, status: :unprocessable_entity
  end

  def certificate_layout
    @layout = @course.certificate_layout_with_defaults
  end

  def update_certificate_layout
    if params[:reset].present?
      @course.update!(certificate_layout: {})
      redirect_to certificate_layout_course_path(@course), notice: t("courses.flash.layout_reset") and return
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
      redirect_to certificate_layout_course_path(@course), notice: t("courses.flash.layout_saved")
    else
      @layout = @course.certificate_layout_with_defaults
      render :certificate_layout, status: :unprocessable_entity
    end
  end

  def destroy
    unless @course.destroy
      return redirect_to course_path(@course), alert: @course.errors.full_messages.to_sentence
    end
    redirect_to courses_path, notice: t("courses.flash.deleted", **helpers.terms), status: :see_other
  end

  def publish
    @course.update(published_at: Time.current)
    redirect_to @course, notice: t("courses.flash.published", **helpers.terms)
  end

  def unpublish
    @course.update(published_at: nil)
    redirect_to @course, notice: t("courses.flash.unpublished", **helpers.terms)
  end

  private

  def course_params
    permitted = params.require(:course).permit(:access_policy, :price_minor, :price_currency, :title, :description, :locale, :subject_id, :published_at, :learning_order, :sequential_lessons, :public_access_enabled, :cover_image, :certificate_template, tag_ids: [], prerequisite_course_ids: [])
    filter_prerequisite_course_ids!(permitted)
    permitted
  end

  def filter_prerequisite_course_ids!(permitted)
    return unless permitted.key?(:prerequisite_course_ids)

    allowed = Course.prerequisite_options_for(except: @course).pluck(:id).map(&:to_s)
    permitted[:prerequisite_course_ids] = Array(permitted[:prerequisite_course_ids]).reject(&:blank?) & allowed
  end
end
