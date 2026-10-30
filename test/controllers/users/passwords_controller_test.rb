require "test_helper"

class Users::PasswordsControllerTest < ActionDispatch::IntegrationTest
  test "public pages offer both password setup and recovery" do
    get new_user_session_path
    assert_select "a", text: "Set or reset password"
    get new_user_password_path
    assert_select "h1", text: "Set or reset your password"
    assert_select "input[type=submit][value='Send password instructions']"
  end

  test "valid token shows setup before first sign-in and reset afterwards" do
    user = users(:student)
    [ [ 0, "Set" ], [ 1, "Reset" ] ].each do |count, action|
      user.update!(sign_in_count: count)
      token = user.send(:set_reset_password_token)
      get edit_user_password_path(reset_password_token: token)
      assert_response :success
      assert_select "h1", text: "#{action} your password"
      assert_select "input[type=submit][value='#{action} password']"
    end
  end

  test "invalid and expired tokens do not select setup wording" do
    user = users(:student)
    token = user.send(:set_reset_password_token)
    user.update!(reset_password_sent_at: 7.hours.ago)
    [ token, "invalid-token" ].each do |invalid_token|
      get edit_user_password_path(reset_password_token: invalid_token)
      assert_select "h1", text: "Reset your password"
    end
  end

  test "setup keeps its wording on validation error and saves through Devise" do
    user = users(:student)
    user.update!(sign_in_count: 0)
    token = user.send(:set_reset_password_token)
    password = generated_password
    put user_password_path, params: { user: { reset_password_token: token, password: password, password_confirmation: "different" } }
    assert_select "h1", text: "Set your password"
    put user_password_path, params: { user: { reset_password_token: token, password: password, password_confirmation: password } }
    assert_response :redirect
    assert user.reload.valid_password?(password)
    assert_nil user.reset_password_token
  end
end
