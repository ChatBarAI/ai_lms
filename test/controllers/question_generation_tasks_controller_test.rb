require "test_helper"

class QuestionGenerationTasksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @course = courses(:algebra)
    @lesson = lessons(:intro)
    @lesson.update!(cbai_api_key: "k", cbai_token: "tok_intro")
  end

  test "owner can queue a generation task" do
    sign_in users(:instructor)

    fake_client = Minitest::Mock.new
    fake_client.expect(:create_task, { "id" => "cbai-task-1", "status" => "launched" }, [], payload: Hash)

    CbaiClient.stub(:new, fake_client) do
      assert_difference("QuestionGenerationTask.count", 1) do
        post course_lesson_question_generation_tasks_path(@course, @lesson),
             params: { question_generation_task: { prompt: "focus on basics", count: 3, kind: "multiple_choice", strategy: "vector_similarity" } }
      end
    end

    assert_redirected_to course_lesson_questions_path(@course, @lesson)
    task = QuestionGenerationTask.order(:id).last
    assert_equal "queued", task.status
    assert_equal "cbai-task-1", task.cbai_task_id
  end

  test "non-owner instructor is denied" do
    sign_in users(:other_instructor)
    assert_no_difference("QuestionGenerationTask.count") do
      post course_lesson_question_generation_tasks_path(@course, @lesson),
           params: { question_generation_task: { prompt: "x" } }
    end
    assert_redirected_to root_path
  end

  test "lesson without cbai api key returns alert" do
    @lesson.update!(cbai_api_key: nil)
    sign_in users(:instructor)

    assert_no_difference("QuestionGenerationTask.count") do
      post course_lesson_question_generation_tasks_path(@course, @lesson),
           params: { question_generation_task: { prompt: "x" } }
    end
    assert_redirected_to course_lesson_questions_path(@course, @lesson)
    assert_match(/ChatBar AI API key/, flash[:alert])
  end

  test "cbai client error marks task failed" do
    sign_in users(:instructor)

    CbaiClient.stub(:new, ->(*) { raise CbaiClient::Error, "boom" }) do
      post course_lesson_question_generation_tasks_path(@course, @lesson),
           params: { question_generation_task: { prompt: "x" } }
    end

    assert_redirected_to course_lesson_questions_path(@course, @lesson)
    task = QuestionGenerationTask.order(:id).last
    assert task.failed?
    assert_match(/boom/, task.error_message)
  end
end
