require "test_helper"

class QuestionGenerationTaskTest < ActiveSupport::TestCase
  setup do
    @lesson = lessons(:intro)
  end

  test "auto-generates a callback_secret on create" do
    task = @lesson.question_generation_tasks.create!(prompt: "test")
    assert task.callback_secret.present?
    assert task.callback_secret.length >= 32
  end

  test "status defaults to pending" do
    task = @lesson.question_generation_tasks.create!(prompt: "x")
    assert task.pending?
  end

  test "mark_queued! sets cbai_task_id and payload" do
    task = @lesson.question_generation_tasks.create!(prompt: "x")
    task.mark_queued!(cbai_task_id: "abc123", task_payload: { "foo" => "bar" })
    assert task.queued?
    assert_equal "abc123", task.cbai_task_id
    assert_equal({ "foo" => "bar" }, task.task_payload)
  end

  test "mark_succeeded! stores response and count" do
    task = @lesson.question_generation_tasks.create!(prompt: "x")
    task.mark_succeeded!(response_payload: { "ok" => true }, questions_created_count: 3)
    assert task.succeeded?
    assert_equal 3, task.questions_created_count
  end

  test "mark_failed! truncates very long error messages" do
    task = @lesson.question_generation_tasks.create!(prompt: "x")
    task.mark_failed!("x" * 5000)
    assert task.failed?
    assert task.error_message.length <= 1000
  end
end
