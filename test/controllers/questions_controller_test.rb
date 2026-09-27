require "test_helper"

class QuestionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @course = courses(:algebra)
    @lesson = lessons(:intro)
    @question_one = questions(:intro_q1)
    @question_two = questions(:intro_q2)
  end

  %i[student other_student other_instructor].each do |role|
    test "#{role} cannot access question management pages directly" do
      sign_in users(role)

      [
        course_lesson_questions_path(@course, @lesson),
        course_lesson_question_path(@course, @lesson, @question_one),
        new_course_lesson_question_path(@course, @lesson),
        edit_course_lesson_question_path(@course, @lesson, @question_one)
      ].each do |path|
        get path

        assert_redirected_to root_path
        assert_not_includes response.body, "answer: #{@question_one.correct_answer}"
      end
    end

    test "#{role} cannot mutate questions through direct requests" do
      sign_in users(role)
      original_questions = @lesson.questions.reorder(:id).pluck(:id, :prompt, :correct_answer, :position)

      assert_no_difference("Question.count") do
        post course_lesson_questions_path(@course, @lesson), params: {
          question: { prompt: "Injected question", kind: "free_text", correct_answer: "Injected answer", points: 1 }
        }
        assert_redirected_to root_path

        patch course_lesson_question_path(@course, @lesson, @question_one), params: {
          question: { prompt: "Replaced question", kind: "free_text", correct_answer: "Replaced answer" }
        }
        assert_redirected_to root_path

        delete course_lesson_question_path(@course, @lesson, @question_one)
        assert_redirected_to root_path

        post reorder_course_lesson_questions_path(@course, @lesson),
             params: { ids: [ @question_two.id, @question_one.id ] }, as: :json
        assert_response :forbidden
      end

      assert_equal original_questions, @lesson.questions.reorder(:id).pluck(:id, :prompt, :correct_answer, :position)
    end
  end

  test "student cannot request the question management index as JSON" do
    sign_in users(:student)

    get course_lesson_questions_path(@course, @lesson), as: :json

    assert_response :forbidden
    assert_equal [ "error" ], response.parsed_body.keys
  end

  test "anonymous user must sign in before accessing question management" do
    get course_lesson_questions_path(@course, @lesson)

    assert_redirected_to new_user_session_path
  end

  %i[instructor admin].each do |role|
    test "#{role} can access the lesson question management pages and answer key" do
      sign_in users(role)

      get course_lesson_questions_path(@course, @lesson)
      assert_response :success
      assert_includes response.body, "answer: #{@question_one.correct_answer}"

      get new_course_lesson_question_path(@course, @lesson)
      assert_response :success

      get edit_course_lesson_question_path(@course, @lesson, @question_one)
      assert_response :success
    end
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
