# Enforces Course#sequential_lessons on every learner-facing lesson request, so a
# locked lesson cannot be reached by a direct link or a crafted form post.
# Expects @course to be set.
module LessonGating
  extend ActiveSupport::Concern

  private

  # The signed-in user's active enrolment in @course, looked up once per request.
  def current_enrollment
    return @current_enrollment if defined?(@current_enrollment)

    @current_enrollment = current_user&.enrollments&.find_by(course_id: @course.id, archived_at: nil)
  end

  # { locked lesson id => lesson to complete first } for the current viewer,
  # computed once per request. Owners and admins can open every lesson, so
  # they can preview the whole course.
  def viewer_locked_lessons
    @viewer_locked_lessons ||=
      if !@course.sequential_lessons? || can?(:update, @course)
        {}
      else
        @course.locked_lessons_for(current_enrollment)
      end
  end

  def enforce_lesson_order
    blocker = viewer_locked_lessons[@lesson.id]
    return unless blocker

    message = t("lessons.locked.message", title: blocker.title, **helpers.terms)
    respond_to do |format|
      format.html { redirect_to course_path(@course), alert: message }
      format.json { render json: { error: message }, status: :forbidden }
      format.any { head :forbidden }
    end
  end
end
