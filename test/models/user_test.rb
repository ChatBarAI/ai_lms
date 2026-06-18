require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "fixtures load with expected roles" do
    assert users(:admin).admin?
    assert users(:instructor).instructor?
    assert users(:student).student?
  end

  test "requires email" do
    user = User.new(password: generated_password)
    assert_not user.valid?
    assert_includes user.errors[:email], "can't be blank"
  end

  test "role enum default is student" do
    user = User.new(email: "new@example.com", password: generated_password)
    assert user.student?
  end

  # --- User.from_kinde ---

  KINDE_USER = {
    id: "kp_test_abc123",
    preferred_email: "sso@example.com",
    first_name: "Test",
    last_name: "User",
    picture: "https://example.com/pic.jpg"
  }.freeze

  test "from_kinde creates a new user with correct attributes" do
    assert_difference -> { User.count }, 1 do
      user = User.from_kinde(KINDE_USER)
      assert user.persisted?, user.errors.full_messages.inspect
      assert_equal "kinde",          user.provider
      assert_equal "kp_test_abc123", user.uid
      assert_equal "sso@example.com", user.email
      assert_equal "Test User",       user.name
    end
  end

  test "from_kinde assigns organisation to new user" do
    org = organizations(:entra_org)
    user = User.from_kinde(KINDE_USER.merge(id: "kp_newuser_001", preferred_email: "newuser@example.com"),
                           organization: org)
    assert_equal org.id, user.organization_id
  end

  test "from_kinde attaches org to existing email/password user with no org" do
    existing = users(:student)
    assert_nil existing.organization_id

    kinde_data = KINDE_USER.merge(preferred_email: existing.email, id: "kp_existing_999")
    org = organizations(:entra_org)
    user = User.from_kinde(kinde_data, organization: org)

    assert_equal existing.id, user.id
    assert_equal org.id, user.reload.organization_id
  end

  test "from_kinde does not reassign user already in a different org" do
    # Put student in acme, try to sign in via entra_org connection
    student = users(:student)
    acme = organizations(:acme)
    student.update!(organization: acme)

    entra = organizations(:entra_org)
    kinde_data = KINDE_USER.merge(preferred_email: student.email, id: "kp_crossorg_888")
    User.from_kinde(kinde_data, organization: entra)

    assert_equal acme.id, student.reload.organization_id, "org should not have been changed"
  end

  test "from_kinde finds existing user by provider+uid, not creating duplicate" do
    # Pre-create user via SSO
    existing = User.from_kinde(KINDE_USER.merge(id: "kp_dup_test", preferred_email: "dup@example.com"))

    assert_no_difference -> { User.count } do
      User.from_kinde(KINDE_USER.merge(id: "kp_dup_test", preferred_email: "dup@example.com"))
    end
  end

  test "from_kinde without org does not touch organisation_id" do
    student = users(:student)
    acme = organizations(:acme)
    student.update!(organization: acme)

    kinde_data = KINDE_USER.merge(preferred_email: student.email, id: "kp_noop_777")
    User.from_kinde(kinde_data)

    assert_equal acme.id, student.reload.organization_id
  end
end
