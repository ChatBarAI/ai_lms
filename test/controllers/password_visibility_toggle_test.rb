require "test_helper"

class PasswordVisibilityToggleTest < ActionDispatch::IntegrationTest
  test "login password field has a show/hide toggle" do
    get new_user_session_path

    assert_response :success
    assert_password_toggle "user[password]"
  end

  test "sign-up password and confirmation fields have show/hide toggles" do
    SiteSetting.current.update!(self_service_sign_up_enabled: true)
    get new_user_registration_path

    assert_response :success
    assert_password_toggle "user[password]"
    assert_password_toggle "user[password_confirmation]"
  end

  test "reset password fields have show/hide toggles" do
    token = users(:student).send(:set_reset_password_token)
    get edit_user_password_path(reset_password_token: token)

    assert_response :success
    assert_password_toggle "user[password]"
    assert_password_toggle "user[password_confirmation]"
    assert_select "input[name='user[password]'][autofocus]"
    assert_select "input[name='user[password_confirmation]'][autofocus]", 0
  end

  test "edit account password fields have show/hide toggles" do
    sign_in users(:student)
    get edit_user_registration_path

    assert_response :success
    assert_password_toggle "user[password]"
    assert_password_toggle "user[password_confirmation]"
    assert_password_toggle "user[current_password]"
  end

  test "admin user form password field has a show/hide toggle" do
    sign_in users(:admin)

    get new_admin_user_path
    assert_response :success
    assert_password_toggle "user[password]"

    get edit_admin_user_path(users(:student))
    assert_response :success
    assert_password_toggle "user[password]"
  end

  private

  def assert_password_toggle(name)
    assert_select "[data-controller='password-visibility']:has(input[name='#{name}'])", 1 do
      assert_select "input[type=password][name='#{name}'][data-password-visibility-target='input']"
      assert_select "button[type=button][aria-label='Show password'][aria-pressed='false'][data-action='password-visibility#toggle']"
      assert_select "img[src*='eye'][data-password-visibility-target='showIcon']"
      assert_select "img[src*='eye-slash'][data-password-visibility-target='hideIcon']"
    end
  end
end
