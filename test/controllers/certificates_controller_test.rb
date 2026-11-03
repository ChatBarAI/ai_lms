require "test_helper"

class CertificatesControllerTest < ActionDispatch::IntegrationTest
  test "completed learners can obtain and revisit their certificate after additional lessons are published" do
    course = courses(:algebra)
    enrollment = enrollments(:student_in_algebra)
    course.lessons_required_for_completion.each do |lesson|
      enrollment.progresses.find_or_initialize_by(lesson: lesson).update!(status: :completed)
    end
    assert_not_nil enrollment.reload.completed_at

    lessons(:draft_lesson).update!(published_at: Time.current)
    sign_in users(:student)

    assert_difference "Certificate.count", 1 do
      get course_certificate_path(course)
    end
    assert_response :success
    certificate = Certificate.find_by!(user: users(:student), course: course)
    original_attributes = certificate.attributes

    course.lessons.create!(title: "More optional learning", published_at: Time.current)
    assert_no_difference "Certificate.count" do
      get course_certificate_path(course)
    end
    assert_response :success
    assert_equal original_attributes, certificate.reload.attributes

    get course_lesson_path(course, lessons(:intro))
    assert_response :success
    assert_select "#lesson-course-sidebar [role='progressbar'][aria-valuenow='100']"
  end

  test "incomplete learners cannot obtain a certificate" do
    sign_in users(:student)

    assert_no_difference "Certificate.count" do
      get course_certificate_path(courses(:algebra))
    end
    assert_redirected_to course_path(courses(:algebra))
  end
end
