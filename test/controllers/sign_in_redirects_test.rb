require "test_helper"

class SignInRedirectsTest < ActionDispatch::IntegrationTest
  test "admin signs in to admin dashboard when no stored location exists" do
    password = generated_password
    users(:admin).update!(password: password)

    post user_session_path, params: {
      user: { email: users(:admin).email, password: password }
    }

    assert_redirected_to admin_root_path
  end

  test "admin sign in preserves stored location" do
    password = generated_password
    admin = users(:admin)
    admin.update!(password: password)

    get profile_path
    assert_redirected_to new_user_session_path

    post user_session_path, params: {
      user: { email: admin.email, password: password }
    }

    assert_redirected_to profile_path
  end

  test "student signs in to default root when no stored location exists" do
    password = generated_password
    users(:student).update!(password: password)

    post user_session_path, params: {
      user: { email: users(:student).email, password: password }
    }

    assert_redirected_to root_path
  end
end
