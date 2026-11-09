class KindeAuthController < ApplicationController
  # Skip CSRF for the callback — it arrives via redirect from Kinde
  skip_before_action :verify_authenticity_token, only: :callback

  # Per-organisation SSO entry point. Looks up the org by slug, stores its id in
  # the session so the callback can assign the user to the correct organisation.
  def org_login
    clear_pending_authentication
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
    auth = KindeSdk.auth_url(connection_id: org.kinde_connection_id, prompt: "login", audience: KindeSdk.config.expected_audience)
    bind_authentication_transaction!(auth)
    redirect_to auth[:url], allow_other_host: true
  end

  def login
    clear_pending_authentication
    unless kinde_configured?
      redirect_to new_user_session_path, alert: "Kinde sign-in is not configured."
      return
    end

    site_setting = SiteSetting.current

    auth_options = { audience: KindeSdk.config.expected_audience }
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
    if provider == "google"
      # A connection_id alone does not interrupt an existing Kinde SSO session.
      # Force Kinde to start a fresh login so the Google connection's upstream
      # prompt=select_account setting is applied.
      auth[:url] = auth_url_with_params(
        auth[:url],
        prompt: "login",
        login_hint: normalized_login_hint(params[:login_hint]) || session.delete(:kinde_login_hint)
      )
    end
    # PKCE is enabled by default; persist the code verifier across the redirect
    bind_authentication_transaction!(auth)
    redirect_to auth[:url], allow_other_host: true
  end

  def callback
    unless kinde_configured?
      redirect_to new_user_session_path, alert: "Kinde sign-in is not configured."
      return
    end

    transaction = session.delete(:kinde_transaction)
    pending_org_id = session.delete(:kinde_pending_org_id)
    provider_hint = session.delete(:kinde_provider_hint)
    code_verifier = session.delete(:kinde_code_verifier)
    unless transaction && transaction["expires_at"].to_i > Time.current.to_i &&
           params[:state].present? && code_verifier.present? &&
           ActiveSupport::SecurityUtils.secure_compare(transaction["state"], params[:state].to_s)
      raise ArgumentError, "Invalid or expired authentication transaction"
    end
    tokens = KindeSdk.fetch_tokens(params[:code], code_verifier: code_verifier)
    claims = KindeSdk.validate_jwt_token(tokens)
    identity = claims.fetch("id_token")
    unless identity["nonce"] == transaction["nonce"] &&
           identity["sub"] == claims.fetch("access_token")["sub"] &&
           (identity["azp"].blank? || identity["azp"] == KindeSdk.config.client_id) &&
           (Array(identity["aud"]).size <= 1 || identity["azp"] == KindeSdk.config.client_id)
      raise ArgumentError, "Invalid identity token binding"
    end
    client = KindeSdk.client(tokens)
    kinde_user = client.oauth.get_user.dup
    raise ArgumentError, "Userinfo subject mismatch" unless kinde_user[:id] == identity["sub"]
    kinde_user[:email_verified] = identity["email_verified"] == true &&
      identity["email"] == kinde_user[:preferred_email]
    organization = Organization.find_by(id: pending_org_id) if pending_org_id
    # This must be a tenant-configured, signed claim sourced from the actual
    # authentication connection. Never use the requested connection as proof.
    connection_claim = Rails.application.credentials.dig(:kinde, :connection_id_claim)
    verified_connection = identity[connection_claim] if connection_claim.present?
    if organization && verified_connection != organization.kinde_connection_id
      raise ArgumentError, "Organization connection could not be verified"
    end
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
      if @user.mandatory_sso? && @user.organization_id != organization&.id
        raise ArgumentError, "Required organization SSO flow was not used"
      end
      reset_session
      sign_in @user, event: :authentication, force: true
      session[:sso_authentication] = {
        "user_id" => @user.id, "organization_id" => organization&.id,
        "connection_id" => verified_connection, "expires_at" => identity.fetch("exp")
      }
      redirect_to after_sign_in_path_for(@user)
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
    email = normalized_login_hint(params[:email])
    session[:kinde_login_hint] = email if email
    org = Organization.for_email_domain(email.to_s)
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

  def clear_pending_authentication
    %i[kinde_pending_org_id kinde_provider_hint kinde_code_verifier kinde_transaction].each { |key| session.delete(key) }
  end

  def bind_authentication_transaction!(auth)
    raise ArgumentError, "PKCE verifier missing" if auth[:code_verifier].blank?

    state = SecureRandom.hex(32)
    nonce = SecureRandom.hex(32)
    auth[:url] = auth_url_with_params(auth[:url], state: state, nonce: nonce)
    session[:kinde_code_verifier] = auth[:code_verifier]
    session[:kinde_transaction] = { "state" => state, "nonce" => nonce, "expires_at" => 10.minutes.from_now.to_i }
  end

  def kinde_configured?
    Rails.application.credentials.dig(:kinde, :client_id).present?
  end

  def auth_url_with_params(auth_url, **params)
    uri = URI.parse(auth_url)
    query = URI.decode_www_form(uri.query.to_s)
    params.compact.each do |key, value|
      query.reject! { |existing_key, _existing_value| existing_key == key.to_s }
      query << [ key.to_s, value.to_s ]
    end
    uri.query = URI.encode_www_form(query)
    uri.to_s
  end

  def normalized_login_hint(value)
    email = value.to_s.strip
    email if email.match?(URI::MailTo::EMAIL_REGEXP)
  end
end
