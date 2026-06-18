require "test_helper"

class Admin::ReportsControllerTest < ActionDispatch::IntegrationTest
  test "non-admin cannot view course report" do
    sign_in users(:instructor)
    get report_admin_course_path(courses(:algebra))
    assert_redirected_to root_path
  end

  test "admin can view course report (by slug)" do
    sign_in users(:admin)
    get report_admin_course_path(courses(:algebra))
    assert_response :success
    assert_match "Algebra", response.body
  end

  test "admin can view lesson report" do
    sign_in users(:admin)
    get report_admin_course_lesson_path(courses(:algebra), lessons(:intro))
    assert_response :success
    assert_match "Intro to Algebra", response.body
  end

  test "lesson report shows AI scored answers table when answers exist" do
    sign_in users(:admin)
    get report_admin_course_lesson_path(courses(:algebra), lessons(:advanced))
    assert_response :success
    assert_match "ChatBar AI lesson marking", response.body
    assert_match "9/10", response.body
    assert_match "Explain the commutative property", response.body
  end

  test "lesson report shows pending indicator when answer has no score" do
    question_answers(:scored_answer).update!(ai_score: nil, scored_at: nil)
    sign_in users(:admin)
    get report_admin_course_lesson_path(courses(:algebra), lessons(:advanced))
    assert_response :success
    assert_match "1 pending", response.body
  end

  test "lesson report 404s for lesson outside course" do
    sign_in users(:admin)
    get report_admin_course_lesson_path(courses(:algebra), lessons(:physics_lesson))
    assert_response :not_found
  end

  test "non-admin cannot view lesson report" do
    sign_in users(:instructor)
    get report_admin_course_lesson_path(courses(:algebra), lessons(:intro))
    assert_redirected_to root_path
  end
end
