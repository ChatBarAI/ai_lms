class ProfilesController < ApplicationController
  before_action :authenticate_user!

  def show
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
