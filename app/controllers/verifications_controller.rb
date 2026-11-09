class VerificationsController < ApplicationController
  def show
    response.headers["Cache-Control"] = "no-store"
    @certificate = Certificate.active.find_by!(token: params[:token])
    @course      = @certificate.course
    @user        = @certificate.user
  rescue ActiveRecord::RecordNotFound
    render :not_found, status: :not_found
  end
end
