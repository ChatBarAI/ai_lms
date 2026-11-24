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

  test "admin has the same marking restrictions as instructors" do
    questions(:intro_q1).update!(kind: :free_text)
    answer = QuestionAnswer.create!(enrollment: enrollments(:student_in_algebra), question: questions(:intro_q1), answer_text: "Two")
    report = report_admin_course_lesson_path(courses(:algebra), lessons(:intro))
    sign_in users(:admin)

    [ "", "0", "11", "8.5" ].each do |score|
      patch admin_question_answer_score_path(answer), params: { question_answer: { ai_score: score } }
      assert_redirected_to report
      assert_nil answer.reload.ai_score
    end

    lessons(:intro).update!(cbai_api_key: "test-key")
    patch admin_question_answer_score_path(answer), params: { question_answer: { ai_score: 8 } }
    assert_redirected_to report
    assert_match "can't be marked manually", flash[:alert]
    assert_nil answer.reload.ai_score

    lessons(:intro).update!(cbai_api_key: nil)
    answer.update!(ai_score: 5, scored_at: Time.current)
    patch admin_question_answer_score_path(answer), params: { question_answer: { ai_score: 8 } }
    assert_equal 5, answer.reload.ai_score

    questions(:intro_q1).update!(kind: :multiple_choice)
    answer.update!(ai_score: nil, scored_at: nil)
    patch admin_question_answer_score_path(answer), params: { question_answer: { ai_score: 8 } }
    assert_nil answer.reload.ai_score
  end

  test "admin dashboard and nav point to marking when answers are waiting" do
    questions(:intro_q1).update!(kind: :free_text)
    QuestionAnswer.create!(enrollment: enrollments(:student_in_algebra), question: questions(:intro_q1), answer_text: "Two")
    sign_in users(:admin)

    get admin_root_path
    assert_select "[role=status] a[href=?]", admin_marking_queue_path
    assert_select "nav a[href=?] span", admin_marking_queue_path, text: "1"

    lessons(:intro).update!(cbai_api_key: "test-key")
    get admin_root_path
    assert_select "[role=status]", count: 0
    assert_select "nav a[href=?]", admin_marking_queue_path
    assert_select "nav a[href=?] span", admin_marking_queue_path, count: 0
  end

  test "module report shows pending marking per lesson" do
    questions(:intro_q1).update!(kind: :free_text)
    QuestionAnswer.create!(enrollment: enrollments(:student_in_algebra), question: questions(:intro_q1), answer_text: "Two")
    sign_in users(:admin)

    get report_admin_course_path(courses(:algebra))
    assert_response :success
    assert_select "[role=status] a[href=?]", admin_marking_queue_path
    assert_select "td a[href=?]", admin_marking_queue_path(lesson: lessons(:intro).id), text: "1"
  end
end
