# Lesson and module locks for the current viewer. A lesson is locked when its
# module's prerequisites are unmet (every lesson, blocked by the module) or when
# the module requires lessons in order (blocked by an earlier lesson).
# Included in ApplicationController so any page can show locks; lesson and
# lesson-material controllers also add `before_action :enforce_lesson_order`,
# so a locked lesson cannot be reached by a direct link or a crafted form post.
module LessonGating
  extend ActiveSupport::Concern

  included do
    helper_method :locked_lessons_for_viewer, :missing_prerequisites_for_viewer,
                  :missing_prerequisites_for_enrollment
  end

  private

  # The signed-in user's active enrolment in the course, looked up once per request.
  def enrollment_for_viewer(course)
    @viewer_enrollments ||= {}
    return @viewer_enrollments[course.id] if @viewer_enrollments.key?(course.id)

    @viewer_enrollments[course.id] = current_user&.enrollments&.find_by(course_id: course.id, archived_at: nil)
  end

  def current_enrollment
    enrollment_for_viewer(@course)
  end

  # Unmet prerequisites for enrolment or purchase, once per course per request.
  # Viewer exemptions do not apply to these eligibility checks.
  def missing_prerequisites_for_enrollment(course)
    @enrollment_missing_prerequisites ||= {}
    @enrollment_missing_prerequisites[course.id] ||= course.missing_prerequisites_for(current_user)
  end

  # Prerequisite modules the viewer still has to complete, once per course per
  # request. Owners, admins and learners already enrolled are never locked out.
  def missing_prerequisites_for_viewer(course)
    @viewer_missing_prerequisites ||= {}
    @viewer_missing_prerequisites[course.id] ||=
      if course.prerequisite_courses.empty? || can?(:update, course) || enrollment_for_viewer(course)
        []
      else
        missing_prerequisites_for_enrollment(course)
      end
  end

  # { locked lesson id => what to complete first }, once per course per
  # request. The blocker is a prerequisite Course (every lesson is locked) or
  # an earlier Lesson (lessons in order). Owners and admins can open every
  # lesson, so they can preview the whole course.
  def locked_lessons_for_viewer(course)
    @viewer_locked_lessons ||= {}
    @viewer_locked_lessons[course.id] ||=
      if can?(:update, course)
        {}
      elsif (missing = missing_prerequisites_for_viewer(course)).any?
        course.lessons.published.pluck(:id).index_with(missing.first)
      elsif course.sequential_lessons?
        course.locked_lessons_for(enrollment_for_viewer(course))
      else
        {}
      end
  end

  def enforce_lesson_order
    blocker = locked_lessons_for_viewer(@course)[@lesson.id]
    return unless blocker

    message = helpers.locked_lesson_message(@course, blocker)
    respond_to do |format|
      format.html { redirect_to course_path(@course), alert: message }
      format.json { render json: { error: message }, status: :forbidden }
      format.any { head :forbidden }
    end
  end
end
