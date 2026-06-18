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
end
