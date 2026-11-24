class Admin::CoursesController < Admin::BaseController
  include LearningReports
  before_action :set_course, only: [ :show, :edit, :update, :destroy, :report, :certificate_layout, :update_certificate_layout ]

  def index
    @selected_subject = Subject.find_by(id: params[:subject_id]) if params[:subject_id].present?
    respond_to do |format|
      format.html do
        @sort = params[:sort] == "learning_order" ? "learning_order" : "published_at"
        @courses = Course.includes(:subject, :owner, :lessons)
        @courses = @courses.where(subject_id: @selected_subject.id) if @selected_subject
        @courses = @courses.merge(Course.catalog_order(@sort))
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
    redirect_to report_admin_course_path(@course)
  end

  def new
    @course = Course.new
  end

  def create
    @course = Course.new(course_params)
    @course.owner ||= current_user
    if @course.save
      redirect_to admin_courses_path, notice: "#{Course.model_name.human} created."
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
      redirect_to admin_courses_path, notice: "#{Course.model_name.human} updated."
    else
      @lessons = @course.lessons.order(:position)
      render :edit, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordInvalid => e
    @course.errors.merge!(e.record.errors)
    @lessons = @course.lessons.order(:position)
    render :edit, status: :unprocessable_entity
  end

  def destroy
    unless @course.destroy
      return redirect_to course_path(@course), alert: @course.errors.full_messages.to_sentence
    end
    redirect_to admin_courses_path, notice: "#{Course.model_name.human} deleted.", status: :see_other
  end

  def report
    load_course_report
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
    permitted = params.require(:course).permit(:access_policy, :price_minor, :price_currency, :title, :description, :locale, :subject_id, :owner_id, :published_at, :learning_order, :public_access_enabled, :cover_image, :certificate_template, tag_ids: [], prerequisite_course_ids: [])
    filter_prerequisite_course_ids!(permitted)
    permitted
  end

  def filter_prerequisite_course_ids!(permitted)
    return unless permitted.key?(:prerequisite_course_ids)

    allowed = Course.prerequisite_options_for(except: @course).pluck(:id).map(&:to_s)
    permitted[:prerequisite_course_ids] = Array(permitted[:prerequisite_course_ids]).reject(&:blank?) & allowed
  end
end
