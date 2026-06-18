require "test_helper"

class Admin::LessonsControllerTest < ActionDispatch::IntegrationTest
  test "non-admin cannot view lessons index" do
    sign_in users(:instructor)
    get admin_course_lessons_path(courses(:algebra))
    assert_redirected_to root_path
  end

  test "admin can view lessons index" do
    sign_in users(:admin)
    get admin_course_lessons_path(courses(:algebra))
    assert_response :success
    assert_match "Intro to Algebra", response.body
  end
end
