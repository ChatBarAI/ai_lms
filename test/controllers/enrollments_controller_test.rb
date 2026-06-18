require "test_helper"

class EnrollmentsControllerTest < ActionDispatch::IntegrationTest
  test "create requires authentication" do
    post course_enrollments_path(courses(:algebra))
    assert_redirected_to new_user_session_path
  end

  test "student can enrol in a course" do
    sign_in users(:other_student)
    assert_difference -> { Enrollment.count }, 1 do
      post course_enrollments_path(courses(:algebra))
    end
    assert_redirected_to course_path(courses(:algebra))
  end

  test "re-enrolling is idempotent" do
    sign_in users(:student)
    assert_no_difference -> { Enrollment.count } do
      post course_enrollments_path(courses(:algebra))
    end
  end

  test "destroy removes the current user's enrollment" do
    sign_in users(:student)
    assert_difference -> { Enrollment.count }, -1 do
      delete course_enrollment_path(courses(:algebra), enrollments(:student_in_algebra))
    end
  end
end
