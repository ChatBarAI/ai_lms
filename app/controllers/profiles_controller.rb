class ProfilesController < ApplicationController
  before_action :authenticate_user!

  def show
    certificates = Certificate.where(user: current_user).includes(:course).order(issued_at: :desc)
    completed_enrollments = current_user.enrollments.completed.includes(:course).order(completed_at: :desc)
    @enrollments_by_course = completed_enrollments.index_by(&:course_id)
    @certificate_courses = (certificates.map(&:course) + completed_enrollments.map(&:course))
      .uniq.select { |course| can?(:read, course) }
  end

  def edit
  end

  def update
    if current_user.update(profile_params)
      redirect_to profile_path, notice: t("profiles.flash.updated")
    else
      flash.now[:alert] = t("profiles.flash.update_failed")
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def profile_params
    params.require(:user).permit(:name, :avatar, :locale, course_locales: [])
  end
end
