class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  around_action :switch_locale
  before_action :refresh_terminology
  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :enforce_sso_requirement

  rescue_from CanCan::AccessDenied do |exception|
    respond_to do |format|
      format.html { redirect_to root_path, alert: exception.message }
      format.json { render json: { error: exception.message }, status: :forbidden }
    end
  end

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [ :name ])
    devise_parameter_sanitizer.permit(:account_update, keys: [ :name ])
  end

  private

  # If the signed-in user belongs to an organisation that requires SSO, ensure
  # they authenticated via Kinde (provider == "kinde"). If they have a Devise
  # session (email/password) we sign them out and redirect to the org's SSO
  # entry point so they are forced through their corporate IdP.
  #
  # Exceptions:
  #   - Devise controllers themselves (sign-in, sign-out, password reset) are
  #     exempt to avoid redirect loops.
  #   - The Kinde callback and org SSO login routes are exempt for the same reason.
  #   - Admin users are exempt so super-admins can still access the system even
  #     if they happen to be assigned to an SSO-required org.
  def enforce_sso_requirement
    return unless user_signed_in?
    return if current_user.admin?
    return if devise_controller?
    return if kinde_auth_request?

    org = current_user.organization
    return unless org&.sso_required?
    return if current_user.provider == "kinde"

    sign_out current_user
    app_url = SiteSetting.current.app_url.presence || "#{request.scheme}://#{request.host_with_port}"
    redirect_to org.sso_login_url(app_url),
                allow_other_host: true,
                alert: "#{org.name} requires sign-in via your organisation's single sign-on. Please use the link below."
  end

  # Returns true for requests handled by KindeAuthController or the WorkOS
  # auth controller so we never intercept mid-SSO-flow redirects.
  def kinde_auth_request?
    controller_name == "kinde_auth" || controller_name == "workos_auth"
  end

  def refresh_terminology
    TerminologyApplier.ensure_fresh!
  end

  def switch_locale(&action)
    I18n.with_locale(current_locale, &action)
  end

  def current_locale
    locale = current_user&.locale.presence
    return locale.to_sym if I18n.available_locales.map(&:to_s).include?(locale)

    I18n.default_locale
  end
end
