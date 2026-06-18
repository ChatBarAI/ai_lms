require "test_helper"

class Api::QuestionGenerationTasksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @lesson = lessons(:intro)
    @lesson.update!(cbai_api_key: "k", cbai_id: 1)
    @task = @lesson.question_generation_tasks.create!(prompt: "x")
  end

  test "unknown token returns 404" do
    post "/api/question_generation_tasks/does-not-exist/callback",
         params: { questions: [] }.to_json,
         headers: { "Content-Type" => "application/json" }
    assert_response :not_found
  end

  test "valid callback creates questions and marks succeeded" do
    payload = {
      questions: [
        { prompt: "Q1", kind: "multiple_choice", choices: %w[A B C], correct_answer: "A", points: 1 },
        { prompt: "Q2", kind: "true_false", choices: %w[True False], correct_answer: "True", points: 2 }
      ]
    }

    assert_difference("Question.count", 2) do
      post "/api/question_generation_tasks/#{@task.callback_secret}/callback",
           params: payload.to_json,
           headers: { "Content-Type" => "application/json" }
    end

    assert_response :success
    @task.reload
    assert @task.succeeded?
    assert_equal 2, @task.questions_created_count
  end

  test "second callback for the same task is a no-op" do
    @task.mark_succeeded!(response_payload: {}, questions_created_count: 1)

    assert_no_difference("Question.count") do
      post "/api/question_generation_tasks/#{@task.callback_secret}/callback",
           params: { questions: [ { prompt: "Q", kind: "free_text" } ] }.to_json,
           headers: { "Content-Type" => "application/json" }
    end
    assert_response :success
  end

  test "empty payload marks task failed" do
    post "/api/question_generation_tasks/#{@task.callback_secret}/callback",
         params: {}.to_json,
         headers: { "Content-Type" => "application/json" }
    assert_response :unprocessable_entity
    assert @task.reload.failed?
  end

  test "unknown question kind falls back to free_text" do
    payload = { questions: [ { prompt: "Q?", kind: "weird_kind" } ] }
    assert_difference("Question.count", 1) do
      post "/api/question_generation_tasks/#{@task.callback_secret}/callback",
           params: payload.to_json,
           headers: { "Content-Type" => "application/json" }
    end
    assert_equal "free_text", Question.order(:id).last.kind
  end
end
