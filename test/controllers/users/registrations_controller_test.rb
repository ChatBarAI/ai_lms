require "test_helper"

class Users::RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "signed in user changes password without the current password" do
    user = users(:student)
    sign_in user
    password = generated_password

    patch user_registration_path, params: { user: { password: password, password_confirmation: password } }

    assert_response :redirect
    assert user.reload.valid_password?(password)
    get profile_path
    assert_response :success
  end

  test "password confirmation must match" do
    user = users(:student)
    sign_in user
    original_password = user.encrypted_password

    patch user_registration_path, params: { user: { password: generated_password, password_confirmation: "different" } }

    assert_equal original_password, user.reload.encrypted_password
    assert_select "li", text: /Password confirmation/
  end

  test "blank password fields preserve the existing password" do
    user = users(:student)
    user.update!(password: generated_password)
    original_password = user.encrypted_password
    sign_in user

    patch user_registration_path, params: { user: { name: "Updated Name", password: "", password_confirmation: "" } }

    assert_response :redirect
    assert_equal "Updated Name", user.reload.name
    assert_equal original_password, user.encrypted_password
  end

  test "anonymous user cannot change a password" do
    user = users(:student)
    original_password = user.encrypted_password
    password = generated_password

    patch user_registration_path, params: { user: { email: user.email, password: password, password_confirmation: password } }

    assert_redirected_to new_user_session_path
    assert_equal original_password, user.reload.encrypted_password
  end
end
