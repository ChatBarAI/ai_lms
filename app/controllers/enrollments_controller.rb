class EnrollmentsController < ApplicationController
  before_action :authenticate_user!

  def create
    course = Course.find_by(slug: params[:course_id]) || Course.find(params[:course_id])
    enrollment = Enrollment.find_or_initialize_by(user: current_user, course: course)
    enrollment.role ||= :student
    authorize! :create, enrollment
    if enrollment.save
      redirect_to course_path(course), notice: "Enrolled."
    else
      redirect_to course_path(course), alert: enrollment.errors.full_messages.to_sentence
    end
  end

  def destroy
    course = Course.find_by(slug: params[:course_id]) || Course.find(params[:course_id])
    enrollment = current_user.enrollments.find_by!(course_id: course.id)
    enrollment.destroy
    redirect_to course_path(course), notice: "Unenrolled.", status: :see_other
  end
end
