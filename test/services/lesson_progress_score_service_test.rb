require "test_helper"

class LessonProgressScoreServiceTest < ActiveSupport::TestCase
  setup do
    @enrollment = enrollments(:student_in_algebra)
    @progress = progresses(:student_intro)
    @progress.update!(status: :in_progress, score: nil)
  end

  test "scores a true/false answer against a legacy free-text correct answer" do
    questions(:intro_q1).update_columns(kind: Question.kinds[:true_false], correct_answer: "Yes", choices: nil)
    QuestionAnswer.create!(enrollment: @enrollment, question: questions(:intro_q1), answer_text: "true")
    QuestionAnswer.create!(enrollment: @enrollment, question: questions(:intro_q2), answer_text: "4")

    assert_equal 100.0, LessonProgressScoreService.call(@progress)
  end

  test "blank points weigh one point" do
    questions(:intro_q1).update_columns(points: nil)
    questions(:intro_q2).update_columns(points: 3)
    QuestionAnswer.create!(enrollment: @enrollment, question: questions(:intro_q1), answer_text: "2")
    QuestionAnswer.create!(enrollment: @enrollment, question: questions(:intro_q2), answer_text: "wrong")

    assert_equal 25.0, LessonProgressScoreService.call(@progress)
  end
end
