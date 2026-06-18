require "test_helper"

class OrganizationTest < ActiveSupport::TestCase
  test "valid with name; slug auto-assigned from name" do
    org = Organization.new(name: "Initech Inc.")
    assert org.valid?, org.errors.full_messages.inspect
    assert_equal "initech-inc", org.slug
  end

  test "name is required" do
    org = Organization.new
    assert_not org.valid?
    assert_includes org.errors[:name], "can't be blank"
  end

  test "name uniqueness is case-insensitive" do
    Organization.create!(name: "Umbrella")
    dup = Organization.new(name: "umbrella")
    assert_not dup.valid?
    assert_includes dup.errors[:name], "has already been taken"
  end

  test "slug must be lowercase alphanumerics and dashes" do
    org = Organization.new(name: "Bad Slug", slug: "Bad Slug!")
    assert_not org.valid?
    assert_includes org.errors[:slug], "is invalid"
  end

  test "slug uniqueness enforced" do
    Organization.create!(name: "First", slug: "shared")
    dup = Organization.new(name: "Second", slug: "shared")
    assert_not dup.valid?
    assert_includes dup.errors[:slug], "has already been taken"
  end

  test "contact_email format validated when present" do
    org = Organization.new(name: "Bad Email Co", contact_email: "not-an-email")
    assert_not org.valid?
    assert_includes org.errors[:contact_email], "is invalid"
  end

  # --- SSO ---

  test "sso_configured? is false with no connection id" do
    assert_not organizations(:acme).sso_configured?
  end

  test "sso_configured? is true when connection id present" do
    assert organizations(:entra_org).sso_configured?
  end

  test "kinde_connection_id uniqueness enforced" do
    dup = Organization.new(name: "Duplicate SSO", kinde_connection_id: "conn_test_entra_001")
    assert_not dup.valid?
    assert_includes dup.errors[:kinde_connection_id], "has already been taken"
  end

  test "kinde_connection_id can be nil on multiple orgs" do
    # nil is exempt from the uniqueness check
    org1 = Organization.create!(name: "No SSO One")
    org2 = Organization.new(name: "No SSO Two")
    assert org2.valid?, org2.errors.full_messages.inspect
  end

  test "kinde_connection_provider must be microsoft, google, or other" do
    org = Organization.new(name: "Bad Provider", kinde_connection_id: "conn_xyz",
                           kinde_connection_provider: "twitter")
    assert_not org.valid?
    assert_includes org.errors[:kinde_connection_provider], "is not included in the list"
  end

  test "kinde_connection_provider can be nil" do
    org = Organization.new(name: "Nil Provider")
    assert org.valid?, org.errors.full_messages.inspect
  end

  test "sso_login_url returns correct URL" do
    org = organizations(:entra_org)
    assert_equal "https://lms.example.com/auth/org/entra-corp",
                 org.sso_login_url("https://lms.example.com")
  end

  # --- sso_required ---

  test "sso_required defaults to false" do
    org = Organization.create!(name: "Default SSO")
    assert_not org.sso_required?
  end

  test "sso_required cannot be enabled without a connection id" do
    org = Organization.new(name: "No Connection", sso_required: true)
    assert_not org.valid?
    assert_includes org.errors[:sso_required], "cannot be enabled without a Kinde connection ID"
  end

  test "sso_required can be enabled when connection id is present" do
    org = Organization.new(name: "With Connection",
                           kinde_connection_id: "conn_new_abc",
                           sso_required: true)
    assert org.valid?, org.errors.full_messages.inspect
  end

  # --- sso_domain ---

  test "sso_domain is normalised to lowercase" do
    org = Organization.create!(name: "Domain Test", kinde_connection_id: "conn_domain_01",
                               sso_domain: "CONTOSO.COM")
    assert_equal "contoso.com", org.sso_domain
  end

  test "sso_domain uniqueness enforced" do
    organizations(:entra_org) # has sso_domain: entra-corp.example.com
    dup = Organization.new(name: "Dup Domain", kinde_connection_id: "conn_dup_dom",
                           sso_domain: "entra-corp.example.com")
    assert_not dup.valid?
    assert_includes dup.errors[:sso_domain], "has already been taken"
  end

  test "sso_domain blank is stored as nil" do
    org = Organization.create!(name: "No Domain", sso_domain: "")
    assert_nil org.sso_domain
  end

  test "for_email_domain finds org by email domain" do
    org = organizations(:entra_org)
    assert_equal org, Organization.for_email_domain("alice@entra-corp.example.com")
  end

  test "for_email_domain returns nil for unknown domain" do
    assert_nil Organization.for_email_domain("alice@unknown.example.com")
  end

  test "for_email_domain returns nil for blank input" do
    assert_nil Organization.for_email_domain("")
    assert_nil Organization.for_email_domain(nil)
  end

  test "contact_email may be blank" do
    org = Organization.new(name: "Blank Email Co")
    assert org.valid?
  end

  test "to_param returns slug" do
    org = organizations(:acme)
    assert_equal "acme-corp", org.to_param
  end

  test "users dependent: :nullify when org deleted" do
    org = organizations(:acme)
    user = users(:student)
    user.update!(organization: org)
    org.destroy
    assert_nil user.reload.organization_id
  end

  test "enrollments and progresses scope to org users" do
    org = organizations(:acme)
    users(:student).update!(organization: org)
    assert_includes org.enrollments, enrollments(:student_in_algebra)
    assert_includes org.progresses, progresses(:student_intro)
  end

  test "completion_rate computes from progresses" do
    org = organizations(:acme)
    users(:student).update!(organization: org)
    progresses(:student_intro).update!(status: :completed)
    # 1 progress total, all completed → 100%
    assert_equal 100.0, org.completion_rate
  end

  test "completion_rate is 0 with no progresses" do
    assert_equal 0, organizations(:globex).completion_rate
  end
end
