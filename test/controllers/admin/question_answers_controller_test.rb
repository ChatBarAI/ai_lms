require "test_helper"

class Admin::QuestionAnswersControllerTest < ActionDispatch::IntegrationTest
  test "admin can manually score a pending free-text answer" do
    lesson = lessons(:intro)
    enrollment = enrollments(:student_in_algebra)
    progress = progresses(:student_intro)

    questions(:intro_q1).update!(kind: :free_text, correct_answer: "Two", points: 1)
    questions(:intro_q2).update!(kind: :multiple_choice, correct_answer: "4", points: 1)
    answer = QuestionAnswer.create!(
      enrollment: enrollment,
      question: questions(:intro_q1),
      answer_text: "Two-ish"
    )
    QuestionAnswer.create!(
      enrollment: enrollment,
      question: questions(:intro_q2),
      answer_text: "4"
    )
    attempt = progress.quiz_attempts.create!(
      enrollment: enrollment,
      lesson: lesson,
      attempt_number: progress.next_attempt_number,
      status: :pending,
      submitted_at: Time.current
    )

    sign_in users(:admin)
    patch admin_question_answer_score_path(answer), params: { question_answer: { ai_score: 8 } }

    assert_redirected_to report_admin_course_lesson_path(courses(:algebra), lesson)
    assert_equal 8, answer.reload.ai_score
    assert_not_nil answer.scored_at
    assert_equal 90.0, progress.reload.score
    assert attempt.reload.scored?
    assert_equal 90.0, attempt.score
  end
end
