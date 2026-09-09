require "test_helper"

class ProfilesControllerTest < ActionDispatch::IntegrationTest
  test "profile links to the password change form" do
    sign_in users(:student)

    get profile_path

    assert_response :success
    assert_select "a[href=?]", edit_user_registration_path, text: "Change password"

    get edit_user_registration_path

    assert_response :success
    assert_select 'input[type="password"][name="user[password]"]'
    assert_select 'input[type="password"][name="user[password_confirmation]"]'
    assert_select 'input[name="user[current_password]"]', count: 0
  end

  test "updates profile language" do
    user = users(:student)
    sign_in user

    patch profile_path, params: { user: { name: user.name, locale: "de" } }

    assert_redirected_to profile_path
    assert_equal "de", user.reload.locale
  end

  test "updates visible course languages" do
    user = users(:student)
    sign_in user

    patch profile_path, params: { user: { course_locales: [ "", "de" ] } }

    assert_redirected_to profile_path
    assert_equal [ "de" ], user.reload.course_locales
  end

  test "requires at least one visible course language" do
    user = users(:student)
    sign_in user

    patch profile_path, params: { user: { course_locales: [ "" ] } }

    assert_response :unprocessable_entity
    assert_equal %w[en de], user.reload.course_locales
  end

  test "rejects unsupported profile language" do
    user = users(:student)
    sign_in user

    patch profile_path, params: { user: { locale: "fr" } }

    assert_response :unprocessable_entity
    assert_equal "en", user.reload.locale
  end

  test "still updates profile name" do
    user = users(:student)
    sign_in user

    patch profile_path, params: { user: { name: "Renamed Student", locale: "en" } }

    assert_redirected_to profile_path
    assert_equal "Renamed Student", user.reload.name
  end
end
