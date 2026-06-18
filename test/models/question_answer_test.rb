class QuestionAnswerTest < ActiveSupport::TestCase
  test "validates uniqueness of question per enrollment" do
    enrollment = enrollments(:student_in_algebra)
    question = questions(:intro_q1)

    QuestionAnswer.create!(enrollment: enrollment, question: question, answer_text: "First")

    duplicate = QuestionAnswer.new(enrollment: enrollment, question: question, answer_text: "Second")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:enrollment_id], "has already been taken"
  end

  test "validates ai_score is between 1 and 10" do
    qa = QuestionAnswer.new(enrollment: enrollments(:student_in_algebra), question: questions(:intro_q1), answer_text: "x")
    qa.ai_score = 0
    assert_not qa.valid?
    qa.ai_score = 11
    assert_not qa.valid?
    qa.ai_score = 5
    assert qa.valid?
    qa.ai_score = nil
    assert qa.valid?
  end
end
