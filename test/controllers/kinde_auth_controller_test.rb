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
      assert_redirected_to expected_url
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
        get kinde_callback_path, params: { code: "test_code", state: "x" }
      end
      assert_equal "sso-ctrl@example.com", User.last.email
    end
  end

  test "callback redirects to root after successful sign-in" do
    stub_callback(KINDE_USER_PAYLOAD) do
      get kinde_callback_path, params: { code: "test_code", state: "x" }
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

    stub_auth_url do |expected_url|
      get kinde_login_path
      assert_redirected_to expected_url
      assert_equal "google", session[:kinde_provider_hint]
    end
  end

  # ─── callback — org assignment ───────────────────────────────────────────────

  test "callback assigns org to newly created user from org_login flow" do
    org = organizations(:entra_org)

    stub_auth_url(connection_id: org.kinde_connection_id) do
      get org_sso_login_path(org_slug: org.slug)
    end

    stub_callback(KINDE_USER_PAYLOAD) do
      get kinde_callback_path, params: { code: "test_code", state: "x" }
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
        get kinde_callback_path, params: { code: "test_code", state: "x" }
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
        get kinde_callback_path, params: { code: "test_code", state: "x" }
      end
      assert_response :redirect   # signed in, not rejected
      assert_not_equal new_user_session_path, response.location
    end
  end

  # ─── helpers ─────────────────────────────────────────────────────────────────

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

  # Stubs the full KindeSdk token-exchange and get_user chain used in #callback.
  def stub_callback(user_payload, &block)
    oauth_stub = Minitest::Mock.new
    oauth_stub.expect(:get_user, user_payload)

    client_stub = Minitest::Mock.new
    client_stub.expect(:oauth, oauth_stub)

    tokens_stub = { access_token: "tok_test" }

    KindeSdk.stub(:fetch_tokens, tokens_stub) do
      KindeSdk.stub(:client, client_stub) do
        yield
      end
    end

    oauth_stub.verify
    client_stub.verify
  end
end
