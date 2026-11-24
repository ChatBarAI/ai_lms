require "test_helper"

class ManualAnswerScorerTest < ActiveSupport::TestCase
  setup do
    @lesson = lessons(:intro)
    @enrollment = enrollments(:student_in_algebra)
    @progress = progresses(:student_intro)
    questions(:intro_q1).update!(kind: :free_text)
    @answer = QuestionAnswer.create!(enrollment: @enrollment, question: questions(:intro_q1), answer_text: "Two")
    QuestionAnswer.create!(enrollment: @enrollment, question: questions(:intro_q2), answer_text: "4")
  end

  test "scores the answer and recalculates progress" do
    ManualAnswerScorer.call(@answer, "8")

    assert_equal 8, @answer.reload.ai_score
    assert_not_nil @answer.scored_at
    assert_equal 90.0, @progress.reload.score
  end

  test "rejects scores outside 1..10 without saving" do
    [ "", "0", "11", "8.5", "8junk", "-1", nil ].each do |score|
      assert_raises(ActiveRecord::RecordInvalid) { ManualAnswerScorer.call(@answer, score) }
      assert_nil @answer.reload.ai_score
    end
  end

  test "refuses answers that cannot be marked by hand" do
    @lesson.update!(cbai_api_key: "test-key")
    assert_raises(ManualAnswerScorer::NotMarkable) { ManualAnswerScorer.call(@answer.reload, "8") }

    @lesson.update!(cbai_api_key: nil)
    @answer.update!(ai_score: 5, scored_at: Time.current)
    assert_raises(ManualAnswerScorer::NotMarkable) { ManualAnswerScorer.call(@answer.reload, "8") }
    assert_equal 5, @answer.reload.ai_score

    @answer.update!(ai_score: nil, scored_at: nil)
    questions(:intro_q1).update!(kind: :multiple_choice)
    assert_raises(ManualAnswerScorer::NotMarkable) { ManualAnswerScorer.call(QuestionAnswer.find(@answer.id), "8") }
  end

  test "rolls back the score when progress recalculation fails" do
    @progress.errors.add(:base, "Unable to finalize progress")
    LessonProgressScoreService.stub(:call, ->(_progress) { raise ActiveRecord::RecordInvalid, @progress }) do
      assert_raises(ActiveRecord::RecordInvalid) { ManualAnswerScorer.call(@answer, "8") }
    end

    assert_nil @answer.reload.ai_score
  end
end
