class Admin::BaseController < ApplicationController
  include Pagy::Method

  before_action :authenticate_user!
  before_action :require_admin

  layout "admin"

  private

  def require_admin
    redirect_to root_path, alert: "Admin access required." unless current_user&.admin?
  end
end
