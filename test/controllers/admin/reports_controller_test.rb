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
    assert_match "Free-text lesson marking", response.body
    assert_match "9/10", response.body
    assert_match "Explain the commutative property", response.body
  end

  test "lesson report marking table only shows free-text answers" do
    QuestionAnswer.create!(
      enrollment: enrollments(:student_in_algebra),
      question: questions(:intro_q1),
      answer_text: "2"
    )
    questions(:intro_q2).update!(kind: :free_text)
    QuestionAnswer.create!(
      enrollment: enrollments(:student_in_algebra),
      question: questions(:intro_q2),
      answer_text: "Four-ish"
    )

    sign_in users(:admin)
    get report_admin_course_lesson_path(courses(:algebra), lessons(:intro))

    assert_response :success
    assert_match "Free-text lesson marking", response.body
    assert_match "What is 2 + 2?", response.body
    assert_no_match "What is 1 + 1?", response.body
  end

  test "lesson report shows pending indicator when answer has no score" do
    course = Course.create!(
      title: "Pending Report Course",
      slug: "pending-report-course",
      subject: subjects(:math),
      owner: users(:instructor)
    )
    lesson = Lesson.create!(
      course: course,
      title: "Pending Report Lesson",
      position: 1
    )
    question = Question.create!(
      lesson: lesson,
      prompt: "Explain the pending state.",
      kind: :free_text,
      correct_answer: "A pending answer has no score.",
      points: 1,
      position: 1
    )
    enrollment = Enrollment.create!(user: users(:student), course: course)
    QuestionAnswer.create!(
      enrollment: enrollment,
      question: question,
      answer_text: "It has not been scored yet."
    )

    sign_in users(:admin)
    get report_admin_course_lesson_path(course, lesson)
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
