require "test_helper"

class Admin::OrganizationsControllerTest < ActionDispatch::IntegrationTest
  test "non-admin is redirected" do
    sign_in users(:instructor)
    get admin_organizations_path
    assert_redirected_to root_path
  end

  test "admin can list organizations" do
    sign_in users(:admin)
    get admin_organizations_path
    assert_response :success
    assert_match "Acme Corp", response.body
    assert_match "Globex", response.body
  end

  test "admin can view an organization (looked up by slug)" do
    sign_in users(:admin)
    get admin_organization_path(organizations(:acme))
    assert_response :success
    assert_match "Acme Corp", response.body
  end

  test "admin can create an organization" do
    sign_in users(:admin)
    assert_difference -> { Organization.count }, 1 do
      post admin_organizations_path, params: { organization: { name: "New Org" } }
    end
    org = Organization.find_by(name: "New Org")
    assert_equal "new-org", org.slug
    assert_redirected_to admin_organization_path(org)
  end

  test "create with blank name shows errors" do
    sign_in users(:admin)
    assert_no_difference -> { Organization.count } do
      post admin_organizations_path, params: { organization: { name: "" } }
    end
    assert_response :unprocessable_entity
  end

  test "admin can update an organization" do
    sign_in users(:admin)
    patch admin_organization_path(organizations(:acme)),
          params: { organization: { contact_email: "ops@acme.example.com" } }
    assert_redirected_to admin_organization_path(organizations(:acme))
    assert_equal "ops@acme.example.com", organizations(:acme).reload.contact_email
  end

  test "admin can delete an organization" do
    sign_in users(:admin)
    assert_difference -> { Organization.count }, -1 do
      delete admin_organization_path(organizations(:globex))
    end
    assert_redirected_to admin_organizations_path
  end

  # --- SSO fields ---

  test "admin can configure SSO on an organization" do
    sign_in users(:admin)
    patch admin_organization_path(organizations(:acme)), params: {
      organization: {
        kinde_connection_id: "conn_new_test_999",
        kinde_connection_provider: "microsoft",
        sso_auto_enroll: true
      }
    }
    assert_redirected_to admin_organization_path(organizations(:acme))
    acme = organizations(:acme).reload
    assert_equal "conn_new_test_999", acme.kinde_connection_id
    assert_equal "microsoft",         acme.kinde_connection_provider
    assert acme.sso_auto_enroll?
  end

  test "admin can clear SSO connection to disable it" do
    sign_in users(:admin)
    patch admin_organization_path(organizations(:entra_org)), params: {
      organization: { kinde_connection_id: "" }
    }
    assert_redirected_to admin_organization_path(organizations(:entra_org))
    assert_nil organizations(:entra_org).reload.kinde_connection_id
  end

  test "setting duplicate connection_id shows validation error" do
    sign_in users(:admin)
    patch admin_organization_path(organizations(:acme)), params: {
      organization: { kinde_connection_id: organizations(:entra_org).kinde_connection_id }
    }
    assert_response :unprocessable_entity
  end
end
