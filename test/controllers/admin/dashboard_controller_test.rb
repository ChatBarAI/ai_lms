require "test_helper"

class Admin::DashboardControllerTest < ActionDispatch::IntegrationTest
  test "non-admin is redirected" do
    sign_in users(:instructor)
    get admin_root_path
    assert_redirected_to root_path
  end

  test "anonymous is redirected to sign in" do
    get admin_root_path
    assert_redirected_to new_user_session_path
  end

  test "admin sees dashboard with totals and charts" do
    sign_in users(:admin)
    get admin_root_path
    assert_response :success
    assert_match(/Users/, response.body)
    assert_match(/Enrolments/, response.body)
  end

  test "admin dashboard links to marking queue when lessons need marking" do
    questions(:intro_q1).update!(kind: :free_text)
    QuestionAnswer.create!(
      enrollment: enrollments(:student_in_algebra),
      question: questions(:intro_q1),
      answer_text: "Needs review"
    )

    sign_in users(:admin)
    get admin_root_path

    assert_response :success
    assert_match "Lessons needing marking", response.body
    assert_match admin_marking_queue_path, response.body
  end

  test "admin can filter dashboard by organization" do
    sign_in users(:admin)
    users(:student).update!(organization: organizations(:acme))
    get admin_root_path(organization_id: organizations(:acme).id)
    assert_response :success
  end

  test "admin can change range parameter" do
    sign_in users(:admin)
    get admin_root_path(range: 90)
    assert_response :success
  end

  test "invalid range clamps without raising" do
    sign_in users(:admin)
    get admin_root_path(range: 1)
    assert_response :success
    get admin_root_path(range: 9999)
    assert_response :success
  end
end
