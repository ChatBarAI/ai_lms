require "test_helper"

class LessonScoringJobTest < ActiveJob::TestCase
  setup do
    @enrollment = enrollments(:student_in_algebra)
    @lesson = lessons(:intro)
    @lesson.update!(cbai_api_key: "test-key")
    # Reuse the fixture progress record (student_intro) rather than creating a duplicate
    @progress = progresses(:student_intro)
    @progress.update!(status: :in_progress, score: nil)
  end

  test "scores free-text answers via CBAI and updates progress" do
    questions(:intro_q1).update!(kind: :free_text, correct_answer: "Two", points: 1)
    questions(:intro_q2).update!(kind: :multiple_choice, correct_answer: "4", points: 1)

    QuestionAnswer.create!(enrollment: @enrollment, question: questions(:intro_q1), answer_text: "Two-ish")
    QuestionAnswer.create!(enrollment: @enrollment, question: questions(:intro_q2), answer_text: "4")

    client_mock = Minitest::Mock.new
    # score_answer called once for the free-text question
    client_mock.expect(:score_answer, 8, question: "What is 1 + 1?", student_answer: "Two-ish", expected_answer: "Two")

    CbaiClient.stub(:new, client_mock) do
      LessonScoringJob.new.perform(@progress.id)
    end

    client_mock.verify

    qa_ft = QuestionAnswer.find_by!(enrollment: @enrollment, question: questions(:intro_q1))
    assert_equal 8, qa_ft.ai_score
    assert_not_nil qa_ft.scored_at

    @progress.reload
    # free-text: (8/10)*1 = 0.8; MC correct: 1.0; total = 1.8/2 * 100 = 90%
    assert_equal 90.0, @progress.score.to_f
    assert @progress.completed?
  end

  test "skips scoring when no CBAI api key on lesson" do
    @lesson.update!(cbai_api_key: nil)
    QuestionAnswer.create!(enrollment: @enrollment, question: questions(:intro_q1), answer_text: "2")

    assert_no_changes("@progress.reload.score") do
      LessonScoringJob.new.perform(@progress.id)
    end
  end

  test "continues scoring remaining questions when one CBAI call fails" do
    questions(:intro_q1).update!(kind: :free_text, correct_answer: "Two", points: 1)
    questions(:intro_q2).update!(kind: :free_text, correct_answer: "Four", points: 1)

    QuestionAnswer.create!(enrollment: @enrollment, question: questions(:intro_q1), answer_text: "Two")
    QuestionAnswer.create!(enrollment: @enrollment, question: questions(:intro_q2), answer_text: "Four")

    call_count = 0
    stubbed_client = Object.new
    stubbed_client.define_singleton_method(:score_answer) do |**|
      call_count += 1
      raise CbaiClient::Error, "network timeout" if call_count == 1
      9
    end

    CbaiClient.stub(:new, stubbed_client) do
      LessonScoringJob.new.perform(@progress.id)
    end

    assert_equal 2, call_count
    # First question's ai_score stays nil (error), second succeeds
    qa2 = QuestionAnswer.find_by!(enrollment: @enrollment, question: questions(:intro_q2))
    assert_equal 9, qa2.ai_score
  end

  test "is a no-op for a non-existent progress id" do
    assert_nothing_raised { LessonScoringJob.new.perform(-1) }
  end
end
