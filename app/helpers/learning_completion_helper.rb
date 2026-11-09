module LearningCompletionHelper
  def course_completed?(course)
    completed_learning_course_ids.include?(course.id)
  end

  # Existing certificates remain available even when historical progress is missing.
  def certificate_available?(course)
    course_completed?(course) || issued_certificate_course_ids.include?(course.id)
  end

  def completion_popup_course(course)
    return unless course && flash[:popup_certificate_course_id].to_s == course.id.to_s

    course if certificate_available?(course)
  end

  private

  # Batch each lookup once per request, including catalogue card collections.
  def completed_learning_course_ids
    @completed_learning_course_ids ||= current_user ? current_user.enrollments.completed.pluck(:course_id).to_set : Set.new
  end

  def issued_certificate_course_ids
    @issued_certificate_course_ids ||= current_user ? Certificate.where(user: current_user).pluck(:course_id).to_set : Set.new
  end
end
