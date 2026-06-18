require "test_helper"

# Tests for the SSO enforcement hook in ApplicationController and the
# sso_check JSON endpoint in KindeAuthController.
class SsoEnforcementTest < ActionDispatch::IntegrationTest
  # ─── enforce_sso_requirement ─────────────────────────────────────────────────

  test "non-SSO user in sso_required org is signed out and redirected to SSO" do
    # Assign student to the sso_required org and sign in via email/password
    # (provider: nil means a standard Devise session)
    student = users(:student)
    org = organizations(:sso_required_org)
    student.update!(organization: org, provider: nil, uid: nil)

    sign_in student
    get root_path

    assert_response :redirect
    assert_match "/auth/org/locked-corp", response.location
    assert_match "single sign-on", flash[:alert]
  end

  test "Kinde-authenticated user in sso_required org passes through" do
    student = users(:student)
    org = organizations(:sso_required_org)
    student.update!(organization: org, provider: "kinde", uid: "kp_enforce_test")

    sign_in student
    get root_path
    assert_response :success
  end

  test "user with no org is not redirected regardless of provider" do
    student = users(:student)
    student.update!(organization: nil, provider: nil, uid: nil)

    sign_in student
    get root_path
    assert_response :success
  end

  test "user in org with sso_required: false is not redirected" do
    student = users(:student)
    student.update!(organization: organizations(:entra_org), provider: nil, uid: nil)

    sign_in student
    get root_path
    assert_response :success
  end

  test "admin user in sso_required org is not redirected" do
    admin = users(:admin)
    admin.update!(organization: organizations(:sso_required_org), provider: nil, uid: nil)

    sign_in admin
    get root_path
    assert_response :success
  end

  # ─── sso_check endpoint ──────────────────────────────────────────────────────

  test "sso_check returns sso_url for known required domain" do
    get sso_check_path, params: { email: "alice@locked-corp.example.com" },
                        headers: { "Accept" => "application/json" }
    assert_response :success
    json = JSON.parse(response.body)
    assert_not_nil json["sso_url"]
    assert_match "/auth/org/locked-corp", json["sso_url"]
  end

  test "sso_check returns null for domain of non-required org" do
    # entra_org has sso_required: false
    get sso_check_path, params: { email: "alice@entra-corp.example.com" },
                        headers: { "Accept" => "application/json" }
    assert_response :success
    json = JSON.parse(response.body)
    assert_nil json["sso_url"]
  end

  test "sso_check returns null for unknown domain" do
    get sso_check_path, params: { email: "alice@unknown.example.com" },
                        headers: { "Accept" => "application/json" }
    assert_response :success
    json = JSON.parse(response.body)
    assert_nil json["sso_url"]
  end

  test "sso_check returns null for blank email" do
    get sso_check_path, params: { email: "" },
                        headers: { "Accept" => "application/json" }
    assert_response :success
    assert_nil JSON.parse(response.body)["sso_url"]
  end
end
