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

  test "true_false_value maps common spellings and rejects anything else" do
    %w[true True TRUE t yes Y correct True.].each { |v| assert_equal "True", Question.true_false_value(v), v }
    %w[false FALSE f no N incorrect false!].each { |v| assert_equal "False", Question.true_false_value(v), v }
    [ nil, "", "maybe", "truth" ].each { |v| assert_nil Question.true_false_value(v), v.inspect }
  end

  test "true/false correct answer is normalised on save" do
    q = Question.create!(lesson: lessons(:intro), prompt: "Ruby is a language?", kind: :true_false, correct_answer: " yes ")
    assert_equal "True", q.correct_answer
  end

  test "true/false correct answer must be True or False" do
    q = Question.new(lesson: lessons(:intro), prompt: "Ruby is a language?", kind: :true_false, correct_answer: "Maybe")
    assert_not q.valid?
    assert_includes q.errors[:correct_answer], "must be True or False"
  end

  test "blank points are stored as the default and zero stays zero" do
    q = Question.create!(lesson: lessons(:intro), prompt: "?", kind: :free_text, points: nil)
    assert_equal Question::DEFAULT_POINTS, q.points
    assert_equal 1, Question.new.points

    zero = Question.create!(lesson: lessons(:intro), prompt: "?", kind: :free_text, points: 0)
    assert_equal 0, zero.reload.points
    assert_equal 0.0, zero.weight
  end

  test "weight treats a legacy nil as the default" do
    q = questions(:intro_q1)
    q.update_columns(points: nil)
    assert_equal 1.0, q.reload.weight
  end

  test "answer_correct? for true/false accepts the learner's radio value against legacy answers" do
    q = questions(:intro_q1)
    q.update_columns(kind: Question.kinds[:true_false], correct_answer: "Yes", choices: nil)
    q.reload

    assert q.answer_correct?("true")
    assert_not q.answer_correct?("false")
    assert_not q.answer_correct?(nil)
  end

  test "answer_correct? for true/false with an unmappable answer is never correct" do
    q = questions(:intro_q1)
    q.update_columns(kind: Question.kinds[:true_false], correct_answer: "Maybe", choices: nil)

    assert_not q.reload.answer_correct?("true")
    assert_not q.answer_correct?("false")
  end

  test "answer_correct? for multiple choice is case and whitespace insensitive" do
    q = questions(:intro_q1)
    assert q.answer_correct?(" 2 ")
    assert_not q.answer_correct?("3")
    assert_not q.answer_correct?(nil)
  end

  test "answer_correct? is false for free text" do
    assert_not questions(:intro_q_free).answer_correct?("Addition order does not change the sum.")
  end

  test "numeric answers are not treated as True/False" do
    assert_nil Question.true_false_value("1")
    assert_nil Question.true_false_value("0")

    q = questions(:intro_q1)
    q.kind = :true_false
    assert_not q.valid?, "a multiple-choice answer of 2 must not silently become True or False"
    assert_includes q.errors[:correct_answer], "must be True or False"
  end
end
