require "csv"

class Admin::UsersController < Admin::BaseController
  before_action :set_user, only: [ :show, :edit, :update, :destroy, :enroll, :reset_password ]

  def index
    @q = User.includes(:organization).ransack(params[:q])
    @q.sorts = "created_at desc" if @q.sorts.empty?
    @pagy, @users = pagy(:offset, @q.result)
    @organizations = Organization.by_name
  end

  def show
    @enrollments = @user.enrollments.includes(course: :lessons).order(enrolled_at: :desc)
    @ratings_given = @user.ratings.includes(:lesson).order(created_at: :desc).limit(20)
    @recent_completions = Progress.where(enrollment_id: @user.enrollments.select(:id))
                                  .completed
                                  .includes(:lesson)
                                  .order(completed_at: :desc).limit(20)
    @enrollable_courses = Course.where.not(id: @user.courses.select(:id)).order(:title)
  end

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)
    @user.role = permitted_role if permitted_role
    @user.organization_id = permitted_organization_id
    if @user.save
      redirect_to admin_user_path(@user), notice: "User created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    attrs = user_params
    attrs[:role] = permitted_role if permitted_role
    attrs[:organization_id] = permitted_organization_id if organization_id_param_present?
    attrs.delete(:password) if attrs[:password].blank?
    if @user.update(attrs)
      redirect_to admin_user_path(@user), notice: "User updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @user == current_user
      redirect_to admin_users_path, alert: "Cannot delete yourself."
    else
      @user.destroy
      redirect_to admin_users_path, notice: "User deleted.", status: :see_other
    end
  end

  def enroll
    course = Course.find(params[:course_id])
    Enrollment.find_or_create_by!(user: @user, course: course)
    redirect_to admin_user_path(@user), notice: "Enrolled in #{course.title}."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to admin_user_path(@user), alert: e.message
  end

  def reset_password
    @user.send_reset_password_instructions
    redirect_to admin_user_path(@user), notice: "Password reset email sent to #{@user.email}."
  end

  def export
    scope = export_scope

    csv = CSV.generate do |out|
      out << export_headers
      scope.find_each do |u|
        out << [
          u.id,
          u.email,
          u.name,
          u.role,
          u.organization_name,
          u.enrollments_count.to_i,
          u.completed_lessons_count.to_i,
          u.in_progress_lessons_count.to_i,
          u.not_started_lessons_count.to_i,
          u.total_lessons_attempted.to_i,
          u.avg_score&.to_f&.round(1),
          u.highest_score&.to_f,
          u.lowest_score&.to_f,
          u.certificates_earned.to_i,
          u.ratings_given.to_i,
          u.avg_rating_given&.to_f&.round(2),
          u.sign_in_count.to_i,
          u.current_sign_in_ip,
          u.locked_at&.iso8601,
          u.created_at&.iso8601,
          u.last_sign_in_at&.iso8601,
          u.last_activity_at&.iso8601,
          days_since_last_activity(u.last_activity_at),
          active_last_30_days?(u.last_activity_at)
        ]
      end
    end
    send_data csv, filename: export_filename, type: "text/csv"
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def user_params
    params.require(:user).permit(:email, :name, :password)
  end

  def permitted_role
    role = params.dig(:user, :role).to_s
    return if role.blank?
    return role if User.roles.key?(role)

    nil
  end

  def permitted_organization_id
    organization_id = params.dig(:user, :organization_id)
    return nil if organization_id.blank?

    id = organization_id.to_i
    return if id <= 0
    return id if Organization.exists?(id)

    nil
  end

  def organization_id_param_present?
    params[:user].respond_to?(:key?) && params[:user].key?(:organization_id)
  end

  def export_scope
    base = User.ransack(params[:q]).result

    base
      .left_joins(:organization)
      .joins(progress_stats_join_sql)
      .joins(ratings_stats_join_sql)
      .joins(certificate_stats_join_sql)
      .select(export_select_clause)
  end

  def export_headers
    %w[
      id
      email
      name
      role
      organization
      enrollments
      completed_lessons
      in_progress_lessons
      not_started_lessons
      total_lessons_attempted
      avg_score
      highest_score
      lowest_score
      certificates_earned
      ratings_given
      avg_rating_given
      sign_in_count
      current_sign_in_ip
      locked_at
      created_at
      last_sign_in_at
      last_activity_at
      days_since_last_activity
      active_last_30_days
    ]
  end

  def export_select_clause
    <<~SQL.squish
      users.id,
      users.email,
      users.name,
      users.role,
      users.sign_in_count,
      users.current_sign_in_ip,
      users.locked_at,
      users.created_at,
      users.last_sign_in_at,
      organizations.name AS organization_name,
      COALESCE(progress_stats.enrollments_count, 0) AS enrollments_count,
      COALESCE(progress_stats.completed_lessons_count, 0) AS completed_lessons_count,
      COALESCE(progress_stats.in_progress_lessons_count, 0) AS in_progress_lessons_count,
      COALESCE(progress_stats.not_started_lessons_count, 0) AS not_started_lessons_count,
      COALESCE(progress_stats.total_lessons_attempted, 0) AS total_lessons_attempted,
      progress_stats.avg_score AS avg_score,
      progress_stats.highest_score AS highest_score,
      progress_stats.lowest_score AS lowest_score,
      progress_stats.last_progress_at AS last_progress_at,
      COALESCE(cert_stats.certificates_earned, 0) AS certificates_earned,
      COALESCE(rating_stats.ratings_given, 0) AS ratings_given,
      rating_stats.avg_rating_given AS avg_rating_given,
      GREATEST(users.last_sign_in_at, progress_stats.last_progress_at) AS last_activity_at
    SQL
  end

  def progress_stats_join_sql
    <<~SQL.squish
      LEFT JOIN (
        SELECT
          enrollments.user_id AS user_id,
          COUNT(DISTINCT enrollments.id) AS enrollments_count,
          COUNT(progresses.id) AS total_lessons_attempted,
          COUNT(*) FILTER (WHERE progresses.status = #{Progress.statuses[:completed]}) AS completed_lessons_count,
          COUNT(*) FILTER (WHERE progresses.status = #{Progress.statuses[:in_progress]}) AS in_progress_lessons_count,
          COUNT(*) FILTER (WHERE progresses.status = #{Progress.statuses[:not_started]}) AS not_started_lessons_count,
          AVG(progresses.score) FILTER (WHERE progresses.score IS NOT NULL) AS avg_score,
          MAX(progresses.score) FILTER (WHERE progresses.score IS NOT NULL) AS highest_score,
          MIN(progresses.score) FILTER (WHERE progresses.score IS NOT NULL) AS lowest_score,
          MAX(progresses.updated_at) AS last_progress_at
        FROM enrollments
        LEFT JOIN progresses ON progresses.enrollment_id = enrollments.id
        GROUP BY enrollments.user_id
      ) progress_stats ON progress_stats.user_id = users.id
    SQL
  end

  def ratings_stats_join_sql
    <<~SQL.squish
      LEFT JOIN (
        SELECT
          ratings.user_id AS user_id,
          COUNT(ratings.id) AS ratings_given,
          AVG(ratings.stars) FILTER (WHERE ratings.stars IS NOT NULL) AS avg_rating_given
        FROM ratings
        GROUP BY ratings.user_id
      ) rating_stats ON rating_stats.user_id = users.id
    SQL
  end

  def certificate_stats_join_sql
    <<~SQL.squish
      LEFT JOIN (
        SELECT
          certificates.user_id AS user_id,
          COUNT(certificates.id) AS certificates_earned
        FROM certificates
        GROUP BY certificates.user_id
      ) cert_stats ON cert_stats.user_id = users.id
    SQL
  end

  def days_since_last_activity(last_activity_at)
    return nil if last_activity_at.blank?

    (Time.zone.today - last_activity_at.to_date).to_i
  end

  def active_last_30_days?(last_activity_at)
    return false if last_activity_at.blank?

    last_activity_at >= 30.days.ago
  end

  def export_filename
    brand_name = SiteSetting.current.brand_name.to_s.strip
    brand_slug = brand_name.present? ? brand_name.parameterize(separator: "-") : "lms"
    "#{brand_slug}-users-#{Date.current}.csv"
  end
end
