require "test_helper"

class TimeZonesControllerTest < ActionDispatch::IntegrationTest
  test "browser detection requires sign in" do
    patch browser_time_zone_profile_path, params: { time_zone: "Asia/Singapore" }, as: :json
    assert_response :unauthorized
  end

  test "detection updates only the current user's browser zone and preserves the override" do
    user = users(:student)
    user.update!(time_zone: "Europe/Berlin")
    sign_in user

    patch browser_time_zone_profile_path,
      params: { time_zone: "Asia/Singapore", user_id: users(:admin).id }, as: :json

    assert_response :no_content
    assert_equal "Asia/Singapore", user.reload.browser_time_zone
    assert_equal "Europe/Berlin", user.time_zone
    assert_nil users(:admin).reload.browser_time_zone
  end

  test "rejects invalid browser zones without changing the saved value" do
    user = users(:student)
    user.update!(browser_time_zone: "Asia/Singapore")
    sign_in user

    [ "invalid", "UTC+8", [ "Asia/Singapore" ], nil ].each do |zone|
      patch browser_time_zone_profile_path, params: { time_zone: zone }, as: :json
      assert_response :unprocessable_entity
      assert_equal "Asia/Singapore", user.reload.browser_time_zone
    end
  end

  test "profile can select a timezone or return to automatic" do
    user = users(:student)
    user.update!(browser_time_zone: "Asia/Singapore")
    sign_in user

    patch profile_path, params: { user: { time_zone: "Europe/Berlin" } }
    assert_redirected_to profile_path
    assert_equal "Europe/Berlin", user.reload.effective_time_zone

    patch profile_path, params: { user: { time_zone: "" } }
    assert_redirected_to profile_path
    assert_equal "Asia/Singapore", user.reload.effective_time_zone

    patch profile_path, params: { user: { time_zone: "invalid" } }
    assert_response :unprocessable_entity
    assert_equal "Asia/Singapore", user.reload.effective_time_zone
  end

  test "requests use the viewer's zone and restore the previous thread zone" do
    previous_zone = Time.zone
    user = users(:admin)
    user.update!(time_zone: "Asia/Singapore")
    sign_in user

    get profile_path
    assert_response :success
    assert_select '[data-time-zone-effective-value="Asia/Singapore"]'
    assert_equal previous_zone, Time.zone

    sign_out user
    get root_path
    assert_select '[data-controller="time-zone"]', count: 0
    assert_equal previous_zone, Time.zone
  end

  test "recent attempts display local time with a timezone and offset" do
    user = users(:admin)
    user.update!(time_zone: "Asia/Singapore")
    progresses(:student_intro).update_columns(updated_at: Time.utc(2026, 11, 26, 3, 31))
    sign_in user

    get report_admin_course_lesson_path(courses(:algebra), lessons(:intro))
    assert_response :success
    assert_select "td", text: "2026-11-26 11:31 +08 (+08:00)"
  end

  test "publication forms display local time and submit using their original zone" do
    user = users(:admin)
    user.update!(time_zone: "Asia/Singapore")
    course = courses(:algebra)
    course.update!(published_at: Time.utc(2026, 11, 26, 3, 31))
    sign_in user

    get edit_course_path(course)
    assert_response :success
    assert_select 'input[name="course[published_at]"][value=?]', "2026-11-26T11:31:00"
    assert_select 'input[name="form_time_zone"][value=?]', "Asia/Singapore"

    # Another tab may change the preference while this form remains open.
    user.update!(time_zone: "Europe/Berlin")
    patch course_path(course), params: {
      form_time_zone: "Asia/Singapore", course: { published_at: "2026-11-26T12:31" }
    }
    assert_response :redirect
    assert_equal Time.utc(2026, 11, 26, 4, 31), course.reload.published_at
  end
end
