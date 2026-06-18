class VerificationsController < ApplicationController
  def show
    @certificate = Certificate.find_by!(token: params[:token])
    @course      = @certificate.course
    @user        = @certificate.user
  rescue ActiveRecord::RecordNotFound
    render :not_found, status: :not_found
  end
end
