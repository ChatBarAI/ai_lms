require "test_helper"

class Users::PasswordsControllerTest < ActionDispatch::IntegrationTest
  test "completing a reset link verifies the email" do
    user = users(:student)
    user.update_column(:email_verified_at, nil)
    token = user.send(:set_reset_password_token)
    password = generated_password
    put user_password_path, params: { user: { reset_password_token: token, password: password, password_confirmation: password } }
    assert_response :redirect
    assert user.reload.email_verified?
  end

  test "public pages offer both password setup and recovery" do
    get new_user_session_path
    assert_select "a", text: "Set or reset password"
    get new_user_password_path
    assert_select "h1", text: "Set or reset your password"
    assert_select "input[type=submit][value='Send password instructions']"
  end

  test "public reset request explains when the organisation requires SSO" do
    user = users(:student)
    user.update!(organization: organizations(:sso_required_org))
    assert_no_emails do
      post user_password_path, params: { user: { email: user.email } }
    end
    assert_response :unprocessable_entity
    assert_select "[role=alert] p", text: I18n.t("devise.passwords.sso_required")
    assert_select "[role=alert] ul", count: 0
    assert_no_match "prohibited", response.body
  end

  test "several errors are listed under a plain heading" do
    user = users(:student)
    token = user.send(:set_reset_password_token)
    put user_password_path, params: { user: { reset_password_token: token, password: "x", password_confirmation: "y" } }
    assert_select "[role=alert] p", text: /\APlease check the following \d+ issues:\z/
    assert_select "[role=alert] li", minimum: 2
  end

  test "public reset request emails a Kinde-linked user without mandatory SSO" do
    user = users(:student)
    user.update!(provider: "kinde", uid: "kp_public_reset", organization: nil)
    assert_emails 1 do
      post user_password_path, params: { user: { email: user.email } }
    end
    assert_response :redirect
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

  test "visitors get the forgot-password page in their browser language" do
    get new_user_password_path, headers: { "Accept-Language" => "de-AT,de;q=0.9,en;q=0.8" }
    assert_select "h1", text: "Passwort festlegen oder zurücksetzen"

    get new_user_password_path, headers: { "Accept-Language" => "fr-FR,fr;q=0.9,en;q=0.5,de;q=0.4" }
    assert_select "h1", text: "Set or reset your password"

    get new_user_password_path, headers: { "Accept-Language" => "fr-FR" }
    assert_select "h1", text: "Set or reset your password"
  end

  test "German visitor sees the SSO warning in German" do
    user = users(:student)
    user.update!(organization: organizations(:sso_required_org))
    post user_password_path, params: { user: { email: user.email } }, headers: { "Accept-Language" => "de" }
    assert_select "[role=alert] p", text: I18n.t("devise.passwords.sso_required", locale: :de)
  end

  test "reset form labels and validation errors are translated" do
    user = users(:student)
    token = user.send(:set_reset_password_token)
    put user_password_path, params: { user: { reset_password_token: token, password: "x", password_confirmation: "y" } },
                            headers: { "Accept-Language" => "de" }
    assert_select "label", text: "Neues Passwort"
    assert_select "[role=alert] li", text: /Passwortbestätigung stimmt nicht mit Passwort überein/
    assert_select "[role=alert] li", text: /Passwort ist zu kurz \(mindestens \d+ Zeichen\)/
  end
end
