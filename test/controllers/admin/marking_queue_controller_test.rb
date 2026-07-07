require "test_helper"

class Admin::MarkingQueueControllerTest < ActionDispatch::IntegrationTest
  test "non-admin cannot view marking queue" do
    sign_in users(:instructor)

    get admin_marking_queue_path

    assert_redirected_to root_path
  end

  test "admin sees lessons needing manual and AI marking" do
    questions(:intro_q1).update!(kind: :free_text)
    QuestionAnswer.create!(
      enrollment: enrollments(:student_in_algebra),
      question: questions(:intro_q1),
      answer_text: "Needs manual review"
    )

    lessons(:advanced).update!(cbai_api_key: "test-key")
    questions(:intro_q_free).update!(kind: :free_text)
    question_answers(:scored_answer).update!(ai_score: nil, scored_at: nil)

    sign_in users(:admin)
    get admin_marking_queue_path

    assert_response :success
    assert_match "Lessons needing marking", response.body
    assert_match "Manual marking", response.body
    assert_match "Queued for AI marking", response.body
    assert_match "Intro to Algebra", response.body
    assert_match "Quadratic equations", response.body
  end
end
