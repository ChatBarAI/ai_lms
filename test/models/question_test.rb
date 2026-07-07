require "test_helper"

class QuestionTest < ActiveSupport::TestCase
  test "valid fixture" do
    assert questions(:intro_q1).valid?
  end

  test "requires prompt" do
    q = Question.new(lesson: lessons(:intro))
    assert_not q.valid?
    assert_includes q.errors[:prompt], "can't be blank"
  end

  test "choices_list returns array from JSON" do
    q = questions(:intro_q1)
    q.choices_list = %w[a b c]
    q.correct_answer = "a"
    q.save!
    assert_equal %w[a b c], q.reload.choices_list
  end

  test "choices_list returns empty array when blank or invalid JSON" do
    q = questions(:intro_q1)
    q.choices = nil
    assert_equal [], q.choices_list
    q.choices = "not valid json"
    assert_equal [], q.choices_list
  end

  test "kind enum default is multiple_choice" do
    q = Question.new(lesson: lessons(:intro), prompt: "?")
    assert q.multiple_choice?
  end

  test "multiple choice correct answer must exactly match a choice" do
    q = Question.new(
      lesson: lessons(:intro),
      prompt: "Pick one",
      kind: :multiple_choice,
      correct_answer: "A"
    )
    q.choices_list = [ "A", "B" ]

    assert q.valid?
  end

  test "multiple choice correct answer rejects non-matching choice" do
    q = Question.new(
      lesson: lessons(:intro),
      prompt: "Pick one",
      kind: :multiple_choice,
      correct_answer: "a"
    )
    q.choices_list = [ "A", "B" ]

    assert_not q.valid?
    assert_includes q.errors[:correct_answer], "must exactly match one of the choices"
  end

  test "free text correct answer does not need to match choices" do
    q = Question.new(
      lesson: lessons(:intro),
      prompt: "Explain",
      kind: :free_text,
      correct_answer: "Any detailed answer"
    )

    assert q.valid?
  end
end
