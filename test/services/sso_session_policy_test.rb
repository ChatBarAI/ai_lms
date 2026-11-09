require "test_helper"

class SsoSessionPolicyTest < ActiveSupport::TestCase
  test "mandatory SSO requires matching user organization connection and unexpired proof" do
    user = users(:student)
    user.update!(organization: organizations(:sso_required_org), provider: "kinde", uid: "linked")
    proof = { "user_id" => user.id, "organization_id" => user.organization_id,
              "connection_id" => user.organization.kinde_connection_id, "expires_at" => 1.hour.from_now.to_i }
    assert SsoSessionPolicy.allowed?(user, { sso_authentication: proof })
    assert_not SsoSessionPolicy.allowed?(user, {})
    { "user_id" => users(:other_student).id, "organization_id" => organizations(:acme).id,
      "connection_id" => "wrong", "expires_at" => 1.second.ago.to_i }.each do |key, value|
      assert_not SsoSessionPolicy.allowed?(user, { sso_authentication: proof.merge(key => value) })
    end
  end
end
