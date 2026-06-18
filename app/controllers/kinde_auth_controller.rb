class KindeAuthController < ApplicationController
  # Skip CSRF for the callback — it arrives via redirect from Kinde
  skip_before_action :verify_authenticity_token, only: :callback

  # Per-organisation SSO entry point. Looks up the org by slug, stores its id in
  # the session so the callback can assign the user to the correct organisation.
  def org_login
    unless kinde_configured?
      redirect_to new_user_session_path, alert: "Kinde sign-in is not configured."
      return
    end

    org = Organization.find_by(slug: params[:org_slug])
    unless org&.sso_configured?
      redirect_to new_user_session_path, alert: "SSO is not configured for this organisation."
      return
    end

    unless SiteSetting.current.kinde_provider_sign_in_enabled?(org.kinde_connection_provider)
      redirect_to new_user_session_path,
                  alert: "Sign in with #{org.kinde_connection_provider.to_s.humanize} is currently disabled."
      return
    end

    session[:kinde_pending_org_id] = org.id
    session[:kinde_provider_hint] = org.kinde_connection_provider if org.kinde_connection_provider.present?
    auth = KindeSdk.auth_url(connection_id: org.kinde_connection_id)
    session[:kinde_code_verifier] = auth[:code_verifier] if auth[:code_verifier].present?
    redirect_to auth[:url], allow_other_host: true
  end

  def login
    unless kinde_configured?
      redirect_to new_user_session_path, alert: "Kinde sign-in is not configured."
      return
    end

    site_setting = SiteSetting.current

    auth_options = {}
    # Optional: pass connection_id to pre-select Google or Microsoft.
    # Store connection IDs in credentials under kinde: connections: google/microsoft.
    if params[:provider].present?
      provider = params[:provider].to_s
      unless site_setting.kinde_provider_sign_in_enabled?(provider)
        redirect_to new_user_session_path, alert: "Sign in with #{provider.humanize} is currently disabled."
        return
      end

      connection_id = Rails.application.credentials.dig(:kinde, :connections, provider.to_sym)
      auth_options[:connection_id] = connection_id if connection_id.present?
      session[:kinde_provider_hint] = provider
    else
      enabled_providers = []
      enabled_providers << "google" if site_setting.kinde_google_sign_in_enabled?
      enabled_providers << "microsoft" if site_setting.kinde_microsoft_sign_in_enabled?

      if enabled_providers.empty?
        redirect_to new_user_session_path, alert: "SSO sign-in is currently disabled."
        return
      end

      # Generic /kinde/login should behave deterministically when only one
      # provider is enabled, matching the visible button options on the page.
      if enabled_providers.one?
        provider = enabled_providers.first
        connection_id = Rails.application.credentials.dig(:kinde, :connections, provider.to_sym)
        auth_options[:connection_id] = connection_id if connection_id.present?
        session[:kinde_provider_hint] = provider
      end
    end

    auth = KindeSdk.auth_url(**auth_options)
    Rails.logger.debug("[Kinde] auth_url generated: #{auth[:url]}")
    # PKCE is enabled by default; persist the code verifier across the redirect
    session[:kinde_code_verifier] = auth[:code_verifier] if auth[:code_verifier].present?
    redirect_to auth[:url], allow_other_host: true
  end

  def callback
    unless kinde_configured?
      redirect_to new_user_session_path, alert: "Kinde sign-in is not configured."
      return
    end

    code_verifier = session.delete(:kinde_code_verifier)
    tokens = KindeSdk.fetch_tokens(params[:code], code_verifier: code_verifier)
    client = KindeSdk.client(tokens)
    kinde_user = client.oauth.get_user

    pending_org_id = session.delete(:kinde_pending_org_id)
    provider_hint = session.delete(:kinde_provider_hint)
    organization = Organization.find_by(id: pending_org_id) if pending_org_id
    provider_for_policy = organization&.kinde_connection_provider.presence || provider_hint
    site_setting = SiteSetting.current

    unless site_setting.kinde_provider_sign_in_enabled?(provider_for_policy)
      redirect_to new_user_session_path, alert: "Sign in with #{provider_for_policy.to_s.humanize} is currently disabled."
      return
    end

    jit_enabled = if organization
      organization.sso_auto_enroll? && site_setting.kinde_jit_provisioning_enabled_for?(provider_for_policy)
    else
      site_setting.kinde_jit_provisioning_enabled_for?(provider_for_policy)
    end

    # When JIT provisioning is disabled for the provider, only pre-existing users
    # (matched by Kinde uid or email) can sign in.
    unless jit_enabled
      existing_user = User.find_by(provider: "kinde", uid: kinde_user[:id]) ||
                      User.find_by(email: kinde_user[:preferred_email])
      unless existing_user
        Rails.logger.info("[Kinde] SSO sign-in rejected for #{kinde_user[:preferred_email]} — JIT disabled for provider=#{provider_for_policy || 'unknown'}")
        redirect_to new_user_session_path,
                    alert: "No account found for #{kinde_user[:preferred_email]}. Contact your administrator to request access."
        return
      end
    end

    @user = User.from_kinde(kinde_user, organization: organization)

    if @user.persisted?
      sign_in_and_redirect @user, event: :authentication
      flash[:notice] = "Successfully signed in." if is_navigational_format?
    else
      redirect_to new_user_registration_path,
                  alert: @user.errors.full_messages.join("\n")
    end
  rescue StandardError => e
    Rails.logger.error("Kinde auth callback error: #{e.message}")
    redirect_to new_user_session_path, alert: "Sign in failed. Please try again."
  end

  # Email-domain lookup used by the sign-in page JS.
  # GET /auth/sso_check?email=user@contoso.com
  # Returns JSON: { sso_url: "https://..." } or { sso_url: null }
  # Only returns a URL when the org has sso_required: true, so voluntary SSO
  # orgs (sso_required: false) don't hijack users who prefer email/password.
  def sso_check
    org = Organization.for_email_domain(params[:email].to_s)
    if org&.sso_required? && org.sso_configured?
      app_url = SiteSetting.current.app_url.presence ||
                "#{request.scheme}://#{request.host_with_port}"
      render json: { sso_url: org.sso_login_url(app_url) }
    else
      render json: { sso_url: nil }
    end
  end

  def logout
    reset_session
    redirect_to KindeSdk.logout_url, allow_other_host: true
  end

  def logout_callback
    reset_session
    redirect_to root_path, notice: "You have been signed out."
  end

  private

  def kinde_configured?
    Rails.application.credentials.dig(:kinde, :client_id).present?
  end
end
