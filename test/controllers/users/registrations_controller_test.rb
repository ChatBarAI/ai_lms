require "test_helper"

class Users::RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "account settings omits certificate warning when the account has none" do
    user = users(:student)
    sign_in user
    get edit_user_registration_path

    assert_select "button[type=button][data-status-modal-dialog-id-value='delete-account-#{user.id}']"
    assert_select "#delete-account-#{user.id}[role=dialog][aria-hidden=true]" do
      assert_select "p", text: I18n.t("account_deletion.warning")
      assert_select "p", text: /certificates/i, count: 0
      assert_select "form[action='#{user_registration_path}'] input[name=_method][value=delete]"
      assert_select "button[data-dialog-target=closeButton]", text: I18n.t("account_deletion.cancel")
    end
  end

  test "account settings warns about existing certificates" do
    user = users(:student)
    Certificate.create!(user: user, course: courses(:algebra))
    sign_in user

    get edit_user_registration_path

    assert_select "#delete-account-#{user.id} p", text: I18n.t("account_deletion.warning_with_certificates")
  end

  test "deleting own account also deletes active and revoked certificates" do
    user = users(:other_student)
    sign_in user
    Certificate.create!(user: user, course: courses(:algebra))
    Certificate.create!(user: user, course: courses(:draft_course), revoked_at: Time.current)

    assert_difference -> { User.count }, -1 do
      assert_difference -> { Certificate.count }, -2 do
        delete user_registration_path
      end
    end

    assert_response :redirect
    assert_not User.exists?(user.id)
  end

  test "signed in user changes password with the current password" do
    user = users(:student)
    sign_in user
    password = generated_password
    current_password = generated_password
    user.update!(password: current_password)
    sign_in user

    patch user_registration_path, params: { user: { password: password, password_confirmation: password, current_password: current_password } }

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

  test "changing your own email clears its verification" do
    user = users(:student)
    current_password = generated_password
    user.update!(password: current_password)
    sign_in user

    patch user_registration_path, params: { user: { email: "self-chosen@example.com", current_password: current_password } }

    assert_response :redirect
    assert_equal "self-chosen@example.com", user.reload.email
    assert_not user.email_verified?
  end

  test "anonymous user cannot change a password" do
    user = users(:student)
    original_password = user.encrypted_password
    password = generated_password

    patch user_registration_path, params: { user: { email: user.email, password: password, password_confirmation: password } }

    assert_redirected_to new_user_session_path
    assert_equal original_password, user.reload.encrypted_password
  end
  test "missing or incorrect current password cannot change credentials" do
    user = users(:student)
    sign_in user
    original = user.encrypted_password
    [ nil, "incorrect" ].each do |current|
      patch user_registration_path, params: { user: { email: "changed@example.com", password: generated_password, current_password: current } }
      assert_equal original, user.reload.encrypted_password
      assert_not_equal "changed@example.com", user.email
    end
  end

  test "linked SSO user without mandatory SSO changes password with the current password" do
    user = users(:student)
    current_password = generated_password
    user.update!(provider: "kinde", uid: "linked", organization: nil, password: current_password)
    sign_in user
    password = generated_password
    patch user_registration_path, params: { user: { password: password, password_confirmation: password, current_password: current_password } }
    assert_response :redirect
    assert user.reload.valid_password?(password)
  end

  test "linked SSO user sees a read-only email and cannot change it" do
    user = users(:student)
    current_password = generated_password
    user.update!(provider: "kinde", uid: "linked", organization: nil, password: current_password)
    sign_in user

    get edit_user_registration_path
    assert_select "input[type=email][readonly]"
    assert_select "#sso-email-note", text: I18n.t("devise.registrations.sso_email_locked")

    patch user_registration_path, params: { user: { email: "changed@example.com", current_password: current_password } }
    assert_not_equal "changed@example.com", user.reload.email
    assert_select "[role=alert] p", text: I18n.t("devise.registrations.sso_email_locked")
  end

  test "SSO account settings warnings follow the user's language" do
    user = users(:student)
    user.update!(provider: "kinde", uid: "linked", organization: nil, locale: "de")
    sign_in user
    get edit_user_registration_path
    assert_select "#sso-email-note", text: I18n.t("devise.registrations.sso_email_locked", locale: :de)
    assert_match "Single-Sign-on-Konto", response.body
  end

  test "mandatory SSO user cannot change password through account settings" do
    user = users(:student)
    user.update!(organization: organizations(:sso_required_org))
    sign_in user
    original = user.encrypted_password
    password = generated_password
    # Act as a valid SSO session so enforcement doesn't sign the user out first.
    SsoSessionPolicy.stub(:allowed?, true) do
      get edit_user_registration_path
      assert_select "input[name='user[password]']", count: 0
      assert_select "div", text: I18n.t("devise.registrations.sso_password_locked")

      patch user_registration_path, params: { user: { password: password, password_confirmation: password } }
    end
    assert_equal original, user.reload.encrypted_password
    assert_select "[role=alert] p", text: I18n.t("devise.registrations.sso_password_locked")
  end

  test "account settings page follows the user's language" do
    user = users(:student)
    user.update!(locale: "de")
    sign_in user
    get edit_user_registration_path
    assert_select "h1", text: "Konto bearbeiten"
    assert_select "label", text: "E-Mail"
    assert_select "input[type=submit][value=Aktualisieren]"
    assert_select "button", text: "Mein Konto löschen"
    assert_no_match(/Edit User|Unhappy\?|Cancel my account/, response.body)
  end
end
