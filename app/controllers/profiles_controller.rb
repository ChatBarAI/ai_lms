class ProfilesController < ApplicationController
  before_action :authenticate_user!

  def show
    certificates = Certificate.active.where(user: current_user).includes(:course).order(issued_at: :desc)
    completed_enrollments = current_user.enrollments.completed.includes(:course).order(completed_at: :desc)
    @enrollments_by_course = completed_enrollments.index_by(&:course_id)
    @certificate_courses = (certificates.map(&:course) + completed_enrollments.map(&:course))
      .uniq.select { |course| can?(:read, course) && helpers.certificate_available?(course) }
  end

  def edit
    @user = current_user
  end

  # Updates a separate copy of the user so a rejected upload never reaches
  # current_user: the layout and the form preview keep showing the saved
  # avatar instead of an unsaved blob, which has no URL.
  def update
    @user = User.find(current_user.id)
    if @user.update(profile_params)
      redirect_to profile_path, notice: t("profiles.flash.updated")
    else
      flash.now[:alert] = t("profiles.flash.update_failed")
      render :edit, status: :unprocessable_entity
    end
  end

  def browser_time_zone
    zone = params[:time_zone]
    unless zone.is_a?(String) && TZInfo::Timezone.all_identifiers.include?(zone)
      return head :unprocessable_entity
    end

    # This endpoint can only update the signed-in user's detected zone.
    current_user.update!(browser_time_zone: zone) if current_user.browser_time_zone != zone
    head :no_content
  end

  private

  def profile_params
    params.require(:user).permit(:name, :avatar, :locale, :time_zone, course_locales: [])
  end
end
