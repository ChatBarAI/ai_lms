class Users::RegistrationsController < Devise::RegistrationsController
  before_action :ensure_self_service_sign_up_enabled!, only: %i[new create]

  private

  def update_resource(resource, params)
    attributes = params.except(:current_password)
    if attributes[:password].blank?
      attributes.delete(:password)
      attributes.delete(:password_confirmation) if attributes[:password_confirmation].blank?
    end

    password_change = attributes[:password].present?
    email_change = attributes.key?(:email) && attributes[:email] != resource.email

    # Passwords follow the sign-in rule: only mandatory SSO blocks them. The email
    # stays locked for any SSO-linked account because it identifies the SSO link.
    if password_change && resource.mandatory_sso?
      resource.errors.add(:base, t("devise.registrations.sso_password_locked"))
    end
    if email_change && resource.sso_email_locked?
      resource.errors.add(:base, t("devise.registrations.sso_email_locked"))
    end

    if resource.errors.any?
      false
    elsif password_change || email_change
      resource.update_with_password(params)
    else
      resource.update(attributes)
    end
  end

  def ensure_self_service_sign_up_enabled!
    return if SiteSetting.current.self_service_sign_up_enabled?

    redirect_to new_user_session_path,
                alert: "Self-service sign up is disabled. Please use your organization sign-in or contact an administrator."
  end
end
