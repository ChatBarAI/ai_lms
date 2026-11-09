require "test_helper"

# Tests for KindeAuthController — covers both the generic login flow and the
# per-organisation SSO entry point (org_login / callback).
#
# The Kinde SDK makes real HTTP calls, so all external calls are stubbed using
# Minitest::Mock. The stub surface is minimal: we only mock what the controller
# directly calls (KindeSdk.auth_url, KindeSdk.fetch_tokens, KindeSdk.client,
# client.oauth.get_user) without reaching into SDK internals.
class KindeAuthControllerTest < ActionDispatch::IntegrationTest
  # Shared Kinde user payload returned by get_user stubs
  KINDE_USER_PAYLOAD = {
    id: "kp_ctrl_test_001",
    preferred_email: "sso-ctrl@example.com",
    first_name: "Ctrl",
    last_name: "Test",
    picture: nil
  }.freeze

  # ─── org_login ───────────────────────────────────────────────────────────────

  test "org_login redirects to Kinde using org connection_id" do
    org = organizations(:entra_org)

    stub_auth_url(connection_id: org.kinde_connection_id) do |expected_url|
      get org_sso_login_path(org_slug: org.slug)
      assert_equal URI.parse(expected_url).host, URI.parse(response.location).host
      assert session[:kinde_transaction]["state"].present?
    end
  end

  test "org_login stores pending_org_id in session" do
    org = organizations(:entra_org)

    stub_auth_url do
      get org_sso_login_path(org_slug: org.slug)
      assert_equal org.id, session[:kinde_pending_org_id]
    end
  end

  test "org_login with unknown slug shows not-configured error" do
    get org_sso_login_path(org_slug: "does-not-exist")
    assert_redirected_to new_user_session_path
    assert_match "not configured", flash[:alert]
  end

  test "org_login with org that has no connection_id shows not-configured error" do
    get org_sso_login_path(org_slug: organizations(:acme).slug)
    assert_redirected_to new_user_session_path
    assert_match "not configured", flash[:alert]
  end

  test "org_login blocks Google org when Google sign-in is disabled" do
    org = organizations(:google_org)
    SiteSetting.current.update!(kinde_google_sign_in_enabled: false)

    get org_sso_login_path(org_slug: org.slug)

    assert_redirected_to new_user_session_path
    assert_match "Sign in with Google is currently disabled", flash[:alert]
  end

  test "org_login blocks Microsoft org when Microsoft sign-in is disabled" do
    org = organizations(:entra_org)
    SiteSetting.current.update!(kinde_microsoft_sign_in_enabled: false)

    get org_sso_login_path(org_slug: org.slug)

    assert_redirected_to new_user_session_path
    assert_match "Sign in with Microsoft is currently disabled", flash[:alert]
  end

  # ─── callback — generic flow ─────────────────────────────────────────────────

  test "callback signs in and creates user when none exists for JIT-enabled provider" do
    # Establish provider context first; Microsoft JIT is enabled by default.
    stub_auth_url do
      get kinde_login_path(provider: "microsoft")
      assert_equal "microsoft", session[:kinde_provider_hint]
    end

    stub_callback(KINDE_USER_PAYLOAD) do
      assert_difference -> { User.count }, 1 do
        get kinde_callback_path, params: { code: "test_code", state: session[:kinde_transaction]["state"] }
      end
      assert_equal "sso-ctrl@example.com", User.last.email
    end
  end

  test "callback redirects to root after successful sign-in" do
    stub_auth_url { get kinde_login_path(provider: "microsoft") }
    stub_callback(KINDE_USER_PAYLOAD) do
      get kinde_callback_path, params: { code: "test_code", state: session[:kinde_transaction]["state"] }
      assert_response :redirect
      follow_redirect!
      assert_response :success
    end
  end

  test "login blocks explicit Google provider when Google sign-in is disabled" do
    SiteSetting.current.update!(kinde_google_sign_in_enabled: false)

    get kinde_login_path(provider: "google")

    assert_redirected_to new_user_session_path
    assert_match "Sign in with Google is currently disabled", flash[:alert]
  end

  test "login blocks explicit Microsoft provider when Microsoft sign-in is disabled" do
    SiteSetting.current.update!(kinde_microsoft_sign_in_enabled: false)

    get kinde_login_path(provider: "microsoft")

    assert_redirected_to new_user_session_path
    assert_match "Sign in with Microsoft is currently disabled", flash[:alert]
  end

  test "generic login auto-selects Google when it is the only enabled provider" do
    settings = SiteSetting.current
    settings.update!(kinde_google_sign_in_enabled: true, kinde_microsoft_sign_in_enabled: false)

    stub_auth_url do
      get kinde_login_path
      redirect_uri = URI.parse(response.location)
      assert_equal "https", redirect_uri.scheme
      assert_equal "kinde.test", redirect_uri.host
      assert_equal "/oauth2/auth", redirect_uri.path
      assert_equal "login", URI.decode_www_form(redirect_uri.query).to_h["prompt"]
      assert_equal "google", session[:kinde_provider_hint]
    end
  end

  test "Google login passes a valid email to Kinde as login_hint" do
    stub_auth_url do
      get kinde_login_path(provider: "google", login_hint: " brod.justice@gmail.com ")

      redirect_uri = URI.parse(response.location)
      redirect_params = URI.decode_www_form(redirect_uri.query).to_h
      assert_equal "brod.justice@gmail.com", redirect_params["login_hint"]
      assert_equal "login", redirect_params["prompt"]
    end
  end

  test "Google login ignores an invalid login_hint" do
    stub_auth_url do
      get kinde_login_path(provider: "google", login_hint: "not an email")

      redirect_uri = URI.parse(response.location)
      assert_nil URI.decode_www_form(redirect_uri.query).to_h["login_hint"]
    end
  end

  test "Google login uses the email retained by sso_check when the link has no login_hint" do
    get sso_check_path, params: { email: "brod.justice@gmail.com" }, as: :json

    stub_auth_url do
      get kinde_login_path(provider: "google")

      redirect_uri = URI.parse(response.location)
      assert_equal "brod.justice@gmail.com", URI.decode_www_form(redirect_uri.query).to_h["login_hint"]
    end
  end

  # ─── callback — org assignment ───────────────────────────────────────────────

  test "callback assigns org to newly created user from org_login flow" do
    org = organizations(:entra_org)

    stub_auth_url(connection_id: org.kinde_connection_id) do
      get org_sso_login_path(org_slug: org.slug)
    end

    stub_callback(KINDE_USER_PAYLOAD) do
      get kinde_callback_path, params: { code: "test_code", state: session[:kinde_transaction]["state"] }
    end

    user = User.find_by(uid: KINDE_USER_PAYLOAD[:id])
    assert_not_nil user
    assert_equal org.id, user.organization_id
  end

  # ─── callback — sso_auto_enroll: false ───────────────────────────────────────

  test "callback rejects new user when org has sso_auto_enroll disabled" do
    org = organizations(:closed_org)

    stub_auth_url(connection_id: org.kinde_connection_id) do
      get org_sso_login_path(org_slug: org.slug)
    end

    stub_callback(KINDE_USER_PAYLOAD) do
      assert_no_difference -> { User.count } do
        get kinde_callback_path, params: { code: "test_code", state: session[:kinde_transaction]["state"] }
      end
      assert_redirected_to new_user_session_path
      assert_match "No account found", flash[:alert]
    end
  end

  test "callback allows existing user when org has sso_auto_enroll disabled" do
    org = organizations(:closed_org)
    # Pre-create the user (as if an admin invited them via email/password)
    existing = User.create!(email: KINDE_USER_PAYLOAD[:preferred_email],
                            password: Devise.friendly_token[0, 20],
                            organization: org)

    stub_auth_url(connection_id: org.kinde_connection_id) do
      get org_sso_login_path(org_slug: org.slug)
    end

    stub_callback(KINDE_USER_PAYLOAD) do
      assert_no_difference -> { User.count } do
        get kinde_callback_path, params: { code: "test_code", state: session[:kinde_transaction]["state"] }
      end
      assert_response :redirect   # signed in, not rejected
      assert_not_equal new_user_session_path, response.location
    end
  end

  # ─── helpers ─────────────────────────────────────────────────────────────────

  test "callback without pending state never exchanges a code" do
    KindeSdk.stub(:fetch_tokens, ->(*) { flunk "unexpected token exchange" }) do
      get kinde_callback_path, params: { code: "attacker", state: "invalid" }
      assert_redirected_to new_user_session_path
    end
  end

  test "invalid state consumes transaction and cannot be replayed" do
    stub_auth_url { get kinde_login_path(provider: "microsoft") }
    state = session[:kinde_transaction]["state"]
    KindeSdk.stub(:fetch_tokens, ->(*) { flunk "unexpected token exchange" }) do
      get kinde_callback_path, params: { code: "code", state: "wrong" }
      assert_redirected_to new_user_session_path
      get kinde_callback_path, params: { code: "code", state: state }
      assert_redirected_to new_user_session_path
    end
  end

  test "verified organization login grants session proof and logout clears it" do
    org = organizations(:sso_required_org)
    stub_auth_url { get org_sso_login_path(org_slug: org.slug) }
    stub_callback(KINDE_USER_PAYLOAD) do
      get kinde_callback_path, params: { code: "code", state: session[:kinde_transaction]["state"] }
    end
    assert_equal org.id, session[:sso_authentication]["organization_id"]
    get root_path
    assert_response :success
    delete destroy_user_session_path
    assert_nil session[:sso_authentication]
  end

  test "new generic login clears previous organization context" do
    stub_auth_url do
      get org_sso_login_path(org_slug: organizations(:entra_org).slug)
      get kinde_login_path(provider: "microsoft")
    end
    assert_nil session[:kinde_pending_org_id]
  end

  test "valid state with mismatched token nonce is rejected before userinfo" do
    stub_auth_url { get kinde_login_path(provider: "microsoft") }
    state = session[:kinde_transaction]["state"]
    claims = { "id_token" => { "sub" => "user", "nonce" => "wrong" }, "access_token" => { "sub" => "user" } }
    tokens = { access_token: "access", id_token: "identity" }
    KindeSdk.stub(:fetch_tokens, tokens) do
      stub_verified_tokens(tokens, claims) do
        KindeSdk.stub(:client, ->(*) { flunk "unexpected userinfo request" }) do
          get kinde_callback_path, params: { code: "code", state: state }
          assert_redirected_to new_user_session_path
          assert_nil session[:sso_authentication]
        end
      end
    end
  end

  private

  # Stubs KindeSdk.auth_url to return a fake URL and code verifier.
  # Yields the fake URL so callers can assert the redirect target if needed.
  def stub_auth_url(connection_id: nil, &block)
    fake_url = "https://kinde.test/oauth2/auth?stub=1"
    fake_auth = { url: fake_url, code_verifier: "test_verifier_abc" }

    KindeSdk.stub(:auth_url, ->(opts = {}) {
      assert_equal connection_id, opts[:connection_id] if connection_id
      fake_auth
    }) do
      yield fake_url
    end
  end

  # validate_jwt_token is prepended by KindeJwtHardening, so a singleton
  # stub of that method is bypassed. Stub the SDK verification boundary instead
  # and keep the real token-type dispatch running. Crypto checks have separate tests.
  def stub_verified_tokens(tokens, claims)
    verified_types = []
    verifier = ->(token, _jwks_url, _issuer, audience) do
      type = tokens.key(token).to_s
      expected_audience = type == "id_token" ? KindeSdk.config.client_id : KindeSdk.config.expected_audience
      if expected_audience.nil?
        assert_nil audience
      else
        assert_equal expected_audience, audience
      end
      verified_types << type
      { valid: true, payload: claims.fetch(type) }
    end
    KindeSdk.stub(:jwt_validation, verifier) { yield }
    assert_equal tokens.keys.map(&:to_s).sort, verified_types.sort
  end

  # Stubs the full KindeSdk token-exchange and get_user chain used in #callback.
  def stub_callback(user_payload, &block)
    oauth_stub = Minitest::Mock.new
    oauth_stub.expect(:get_user, user_payload)

    client_stub = Minitest::Mock.new
    client_stub.expect(:oauth, oauth_stub)

    tokens_stub = { access_token: "tok_test", id_token: "id_test" }
    org = Organization.find_by(id: session[:kinde_pending_org_id])
    identity = {
      "sub" => user_payload[:id], "nonce" => session[:kinde_transaction]["nonce"],
      "exp" => 1.hour.from_now.to_i, "aud" => KindeSdk.config.client_id,
      "email" => user_payload[:preferred_email], "email_verified" => true,
      "test_connection" => org&.kinde_connection_id
    }
    credentials = Rails.application.credentials
    original_dig = credentials.method(:dig)
    credential_lookup = ->(*keys) { keys == [ :kinde, :connection_id_claim ] ? "test_connection" : original_dig.call(*keys) }

    KindeSdk.stub(:fetch_tokens, tokens_stub) do
      KindeSdk.stub(:client, client_stub) do
        credentials.stub(:dig, credential_lookup) do
          stub_verified_tokens(tokens_stub, { "id_token" => identity, "access_token" => { "sub" => user_payload[:id] } }) do
            yield
          end
        end
      end
    end

    oauth_stub.verify
    client_stub.verify
  end
end
