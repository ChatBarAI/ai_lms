class Users::RegistrationsController < Devise::RegistrationsController
  before_action :ensure_self_service_sign_up_enabled!, only: %i[new create]

  private

  def ensure_self_service_sign_up_enabled!
    return if SiteSetting.current.self_service_sign_up_enabled?

    redirect_to new_user_session_path,
                alert: "Self-service sign up is disabled. Please use your organization sign-in or contact an administrator."
  end
end
