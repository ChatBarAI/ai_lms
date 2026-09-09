class Users::RegistrationsController < Devise::RegistrationsController
  before_action :ensure_self_service_sign_up_enabled!, only: %i[new create]

  private

  def update_resource(resource, params)
    attributes = params.except(:current_password)
    if attributes[:password].blank?
      attributes.delete(:password)
      attributes.delete(:password_confirmation) if attributes[:password_confirmation].blank?
    end

    resource.update(attributes)
  end

  def ensure_self_service_sign_up_enabled!
    return if SiteSetting.current.self_service_sign_up_enabled?

    redirect_to new_user_session_path,
                alert: "Self-service sign up is disabled. Please use your organization sign-in or contact an administrator."
  end
end
