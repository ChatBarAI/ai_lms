class HomeController < ApplicationController
  before_action :authenticate_user!, only: :me

  def index
    if SiteSetting.current.allow_guest_access? || user_signed_in?
      @subjects = Subject.includes(:courses).order(:name)
      recent_courses = Course.published.includes(:tags).order(published_at: :desc).limit(6)
      recent_lessons = Lesson.published.includes(:tags, course: :subject).order(published_at: :desc).limit(6)
      @recent_items = (recent_courses + recent_lessons).sort_by(&:published_at).reverse.first(6)
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
