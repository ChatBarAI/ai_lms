class HomeController < ApplicationController
  before_action :authenticate_user!, only: :me

  def index
    if SiteSetting.current.allow_guest_access? || user_signed_in?
      course_scope = Course.catalog_visible_to(current_user)
      @show_recent_section = user_signed_in? || course_scope.exists?
      allowed_types = SiteSetting.current.subjects_enabled? ? %w[subjects courses lessons] : %w[courses lessons]
      @recent_type = allowed_types.include?(params[:recent]) ? params[:recent] : "courses"
      @recent_items = case @recent_type
      when "subjects"
        Subject.joins(:courses).merge(course_scope)
          .select("subjects.*, COUNT(courses.id) AS visible_courses_count")
          .group("subjects.id")
          .order(Arel.sql("MAX(courses.published_at) DESC"), id: :desc).limit(6)
      when "lessons"
        Lesson.published.where(course_id: course_scope.select(:id))
          .includes(:tags, :rich_text_body, :course, cover_image_attachment: :blob)
          .order(published_at: :desc, id: :desc).limit(6)
      else
        course_scope.includes(:tags).order(published_at: :desc, id: :desc).limit(6)
      end
    end
  end

  def me
    @enrollments = current_user.enrollments.includes(course: :lessons).order(:enrolled_at)

    enrollment_ids = @enrollments.map(&:id)
    @quiz_attempts_by_enrollment = if enrollment_ids.any?
      QuizAttempt.includes(:lesson)
                 .where(enrollment_id: enrollment_ids)
                 .order(:enrollment_id, :submitted_at, :attempt_number)
                 .to_a
                 .group_by(&:enrollment_id)
    else
      {}
    end
    @default_pass_mark = SiteSetting.current.pass_mark

    @course_completion = @enrollments.each_with_object({}) do |e, h|
      h[e.course.title] = e.completion_percentage
    end

    @completed_per_week = current_user.progresses
                                      .where(status: Progress.statuses[:completed])
                                      .group_by_week(:completed_at, last: 12)
                                      .count
  end
end
