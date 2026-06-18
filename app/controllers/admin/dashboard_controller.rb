class Admin::DashboardController < Admin::BaseController
  def index
    @organization = Organization.find_by(id: params[:organization_id]) if params[:organization_id].present?
    @organizations = Organization.by_name
    @range_days = (params[:range] || 30).to_i.clamp(7, 365)
    since = @range_days.days.ago.beginning_of_day

    users_scope = User.all
    users_scope = users_scope.where(organization_id: @organization.id) if @organization
    enrollments_scope = Enrollment.all
    enrollments_scope = enrollments_scope.where(user_id: users_scope.select(:id)) if @organization
    progresses_scope = Progress.all
    progresses_scope = progresses_scope.where(enrollment_id: enrollments_scope.select(:id)) if @organization

    @total_users = users_scope.count
    @active_users = users_scope.active_since(since).count
    @total_enrollments = enrollments_scope.count
    @completions_this_month = progresses_scope.completed.where(completed_at: Time.current.beginning_of_month..).count
    @total_courses = Course.count
    @total_lessons = Lesson.count

    avg = enrollments_scope.includes(:course).map(&:completion_percentage)
    @avg_completion = avg.any? ? (avg.sum / avg.size).round(1) : 0

    # Keep chart ranges stable and fill gaps with zeros so short windows still render.
    @sign_ins_per_day = users_scope.where(last_sign_in_at: since..)
                     .group_by_day(:last_sign_in_at, range: since..Time.current.end_of_day, series: true, default_value: 0)
                     .count
    @enrollments_per_week = enrollments_scope.where(enrolled_at: since..)
                          .group_by_week(:enrolled_at, range: since..Time.current.end_of_day, series: true, default_value: 0)
                          .count
    @completions_per_week = progresses_scope.completed.where(completed_at: since..)
                          .group_by_week(:completed_at, range: since..Time.current.end_of_day, series: true, default_value: 0)
                          .count

    top_course_ids = enrollments_scope.group(:course_id).order(Arel.sql("COUNT(*) DESC")).limit(5).count
    @top_courses_by_enrollment = Course.where(id: top_course_ids.keys).index_by(&:id)
                                       .then { |h| top_course_ids.transform_keys { |id| h[id]&.title || "?" } }

    @top_rated_lessons = Lesson.joins(:ratings).group("lessons.id", "lessons.title")
                               .order(Arel.sql("AVG(ratings.stars) DESC"))
                               .limit(5).average("ratings.stars")
                               .transform_keys { |k| k.is_a?(Array) ? k.last : k }
  end
end
