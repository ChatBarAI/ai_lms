require "test_helper"

class QuestionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @course = courses(:algebra)
    @lesson = lessons(:intro)
    @question_one = questions(:intro_q1)
    @question_two = questions(:intro_q2)
  end

  test "instructor can reorder questions with json payload" do
    sign_in users(:instructor)

    post reorder_course_lesson_questions_path(@course, @lesson),
         params: { ids: [ @question_two.id, @question_one.id ] }.to_json,
         headers: {
           "CONTENT_TYPE" => "application/json",
           "ACCEPT" => "application/json"
         }

    assert_response :no_content
    assert_equal [ @question_two.id, @question_one.id ], @lesson.questions.reorder(:position).pluck(:id)
  end

  test "index renders questions in persisted position order" do
    @question_one.update_column(:position, 2)
    @question_two.update_column(:position, 1)
    sign_in users(:instructor)

    get course_lesson_questions_path(@course, @lesson)

    assert_response :success
    assert_operator response.body.index(@question_two.prompt), :<, response.body.index(@question_one.prompt)
  end

  test "invalid multiple choice create shows validation error and preserves choices" do
    sign_in users(:instructor)

    assert_no_difference("Question.count") do
      post course_lesson_questions_path(@course, @lesson), params: {
        question: {
          prompt: "What is 2 + 2?",
          kind: "multiple_choice",
          choices_list: [ "2", "4" ],
          correct_answer: "5",
          points: "1"
        }
      }
    end

    assert_response :unprocessable_entity
    assert_match "Correct answer must exactly match one of the choices", response.body
    assert_match "2\n4", response.body
  end
end
