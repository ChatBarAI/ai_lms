class Admin::CoursesController < Admin::BaseController
  before_action :set_course, only: [ :show, :edit, :update, :destroy, :report, :certificate_layout, :update_certificate_layout ]

  def index
    @selected_subject = Subject.find_by(id: params[:subject_id]) if params[:subject_id].present?
    respond_to do |format|
      format.html do
        @courses = Course.includes(:subject, :owner, :lessons)
        @courses = @courses.where(subject_id: @selected_subject.id) if @selected_subject
        @courses = @courses.order(created_at: :desc)
      end

      format.csv do
        csv_scope = Course.admin_csv_scope(subject_id: @selected_subject&.id)
        send_data Course.to_admin_csv(csv_scope),
                  filename: Course.admin_csv_filename(brand_name: SiteSetting.current.brand_name),
                  type: "text/csv"
      end
    end
  end

  def show
  end

  def new
    @course = Course.new
  end

  def create
    @course = Course.new(course_params)
    @course.owner ||= current_user
    if @course.save
      redirect_to admin_courses_path, notice: "Course created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @lessons = @course.lessons.order(:position)
  end

  def update
    @course.cover_image.purge if ActiveModel::Type::Boolean.new.cast(params.dig(:course, :remove_cover_image))
    @course.certificate_template.purge if ActiveModel::Type::Boolean.new.cast(params.dig(:course, :remove_certificate_template))
    if @course.update(course_params)
      redirect_to admin_courses_path, notice: "Course updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @course.destroy
    redirect_to admin_courses_path, notice: "Course deleted.", status: :see_other
  end

  def report
    enrollments = @course.enrollments
    progresses = @course.progresses

    @enrollment_count = enrollments.count
    @active_learners = @course.active_learners_count
    @completion_rate = @course.completion_rate
    @average_score = @course.average_score
    @average_rating = @course.average_rating

    @enrollments_per_week = enrollments.where(enrolled_at: 12.weeks.ago..).group_by_week(:enrolled_at).count
    @completions_per_week = progresses.completed.where(completed_at: 12.weeks.ago..).group_by_week(:completed_at).count
    @score_distribution = progresses.with_score.group("FLOOR(score / 10) * 10").count
                                     .transform_keys { |k| "#{k.to_i}–#{k.to_i + 9}" }

    @top_learners = enrollments.includes(:user, :progresses)
                                .sort_by { |e| -e.lessons_completed_count }
                                .first(10)

    @lesson_summary = @course.lessons.order(:position).map do |lesson|
      {
        lesson: lesson,
        attempts: lesson.attempts_count,
        completions: lesson.completions_count,
        average_score: lesson.average_score,
        pass_rate: lesson.pass_rate,
        average_rating: lesson.average_rating
      }
    end
  end

  def certificate_layout
    @layout = @course.certificate_layout_with_defaults
  end

  def update_certificate_layout
    if params[:reset].present?
      @course.update!(certificate_layout: {})
      redirect_to certificate_layout_admin_course_path(@course), notice: "Layout reset to defaults." and return
    end

    layout = (params[:layout] || {}).to_unsafe_h.slice(*Course::CERTIFICATE_FIELDS)
    cleaned = layout.each_with_object({}) do |(key, attrs), h|
      defaults = Course::DEFAULT_CERTIFICATE_LAYOUT[key]
      h[key] = {
        "x"     => attrs["x"].to_f.clamp(0, 100),
        "y"     => attrs["y"].to_f.clamp(0, 100),
        "size"  => attrs["size"].to_f.clamp(6, 120),
        "align" => %w[left center right].include?(attrs["align"]) ? attrs["align"] : "center",
        "bold"  => ActiveModel::Type::Boolean.new.cast(attrs["bold"]) || false
      }
    end

    if @course.update(certificate_layout: cleaned)
      redirect_to certificate_layout_admin_course_path(@course),
                  notice: "Certificate layout saved."
    else
      @layout = @course.certificate_layout_with_defaults
      render :certificate_layout, status: :unprocessable_entity
    end
  end

  private

  def set_course
    @course = Course.find_by(slug: params[:id]) || Course.find(params[:id])
  end

  def course_params
    params.require(:course).permit(:title, :description, :subject_id, :owner_id, :published_at, :cover_image, :certificate_template, tag_ids: [])
  end
end
