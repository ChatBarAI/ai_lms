require "test_helper"

class InstructorAssessmentTest < ActionDispatch::IntegrationTest
  setup do
    @course = courses(:algebra)
    @lesson = lessons(:intro)
    @enrollment = enrollments(:student_in_algebra)
    @progress = progresses(:student_intro)
    questions(:intro_q1).update!(kind: :free_text)
    @answer = QuestionAnswer.create!(enrollment: @enrollment, question: questions(:intro_q1), answer_text: "Two")
    QuestionAnswer.create!(enrollment: @enrollment, question: questions(:intro_q2), answer_text: "4")
    @attempt = @progress.quiz_attempts.create!(
      enrollment: @enrollment, lesson: @lesson,
      attempt_number: @progress.next_attempt_number, status: :pending, submitted_at: Time.current
    )
  end

  test "owner can view reports and navigate without admin links" do
    sign_in users(:instructor)

    get report_course_path(@course)
    assert_response :success
    assert_select "a[href=?]", report_course_lesson_path(@course, @lesson)
    assert_select "a[href^='/admin']", count: 0

    get report_course_lesson_path(@course, @lesson)
    assert_response :success
    assert_select "a[href=?]", question_path
    assert_select "a[href=?]", report_course_path(@course)
    assert_select "a[href^='/admin']", count: 0

    get question_path
    assert_response :success
    assert_match @answer.answer_text, response.body
    assert_match users(:student).email, response.body
    assert_select "form[action=?] input[name=return_to][value=?]", score_path, question_path
    assert_select "a[href^='/admin']", count: 0

    get course_path(@course)
    assert_select "a[href=?]", report_course_path(@course)
    assert_select "a[href=?]", marking_queue_path

    get course_lesson_path(@course, @lesson)
    assert_select "a[href=?]", report_course_lesson_path(@course, @lesson)
  end

  test "owner can report on draft modules and lessons" do
    sign_in users(:instructor)
    get report_course_path(courses(:draft_course))
    assert_response :success
    get report_course_lesson_path(@course, lessons(:draft_lesson))
    assert_response :success
  end

  test "marking queue only includes owned lessons" do
    lessons(:advanced).update!(cbai_api_key: "test-key")
    question_answers(:scored_answer).update!(ai_score: nil, scored_at: nil)
    other_lesson = lessons(:physics_lesson)
    other_question = other_lesson.questions.create!(prompt: "Explain gravity", kind: :free_text, correct_answer: "Gravity", points: 1, position: 1)
    other_enrollment = Enrollment.create!(user: users(:other_student), course: other_lesson.course)
    QuestionAnswer.create!(enrollment: other_enrollment, question: other_question, answer_text: "Gravity")
    sign_in users(:instructor)

    get marking_queue_path
    assert_response :success
    assert_select "a[href=?]", report_course_lesson_path(@course, @lesson)
    assert_select "a[href=?]", report_course_lesson_path(@course, lessons(:advanced))
    assert_match "Queued for AI marking", response.body
    assert_select "a[href=?]", report_course_lesson_path(other_lesson.course, other_lesson), count: 0
    assert_no_match other_lesson.title, response.body
    assert_select "a[href^='/admin']", count: 0
  end

  test "marking recalculates progress and finalizes the pending attempt" do
    sign_in users(:instructor)
    patch score_path, params: { question_answer: { ai_score: 8, answer_text: "Tampered" } }

    assert_redirected_to report_course_lesson_path(@course, @lesson)
    assert_equal 8, @answer.reload.ai_score
    assert_equal "Two", @answer.answer_text
    assert_not_nil @answer.scored_at
    assert_equal 90.0, @progress.reload.score
    assert @progress.completed?
    assert @attempt.reload.scored?
    assert_equal 90.0, @attempt.score

    get marking_queue_path
    assert_select "a[href=?]", report_course_lesson_path(@course, @lesson), count: 0
  end

  test "partial marking waits until every free-text answer is scored" do
    questions(:intro_q2).update!(kind: :free_text)
    second_answer = QuestionAnswer.find_by!(enrollment: @enrollment, question: questions(:intro_q2))
    sign_in users(:instructor)

    patch score_path, params: { question_answer: { ai_score: 8 } }
    assert_equal 8, @answer.reload.ai_score
    assert_nil @progress.reload.score
    assert @attempt.reload.pending?

    patch course_lesson_question_answer_score_path(@course, @lesson, second_answer), params: { question_answer: { ai_score: 10 } }
    assert_equal 90.0, @progress.reload.score
    assert @attempt.reload.scored?
  end

  test "invalid scores leave answer progress and attempt unchanged" do
    sign_in users(:instructor)
    [ "", "0", "11", "8.5", "8junk", "-1" ].each do |score|
      patch score_path, params: { question_answer: { ai_score: score } }
      assert_redirected_to report_course_lesson_path(@course, @lesson)
      assert_not_nil flash[:alert]
      assert_nil @answer.reload.ai_score
      assert_nil @answer.scored_at
      assert_nil @progress.reload.score
      assert @attempt.reload.pending?
    end
  end

  test "failed recalculation rolls back the saved answer" do
    sign_in users(:instructor)
    @progress.errors.add(:base, "Unable to finalize progress")
    LessonProgressScoreService.stub(:call, ->(_progress) { raise ActiveRecord::RecordInvalid, @progress }) do
      patch score_path, params: { question_answer: { ai_score: 8 } }
    end

    assert_redirected_to report_course_lesson_path(@course, @lesson)
    assert_match "Unable to finalize progress", flash[:alert]
    assert_nil @answer.reload.ai_score
    assert_nil @answer.scored_at
    assert_nil @progress.reload.score
    assert @attempt.reload.pending?
  end

  test "owner cannot mark AI queued answers or overwrite an existing score" do
    sign_in users(:instructor)
    @lesson.update!(cbai_api_key: "test-key")
    patch score_path, params: { question_answer: { ai_score: 8 } }
    assert_redirected_to root_path
    assert_nil @answer.reload.ai_score

    @lesson.update!(cbai_api_key: nil)
    @answer.update!(ai_score: 5, scored_at: Time.current)
    patch score_path, params: { question_answer: { ai_score: 8 } }
    assert_redirected_to root_path
    assert_equal 5, @answer.reload.ai_score
  end

  test "owner cannot score choice answers or use mismatched nested resources" do
    sign_in users(:instructor)
    questions(:intro_q1).update!(kind: :multiple_choice)
    patch score_path, params: { question_answer: { ai_score: 8 } }
    assert_redirected_to root_path
    assert_nil @answer.reload.ai_score

    patch course_lesson_question_answer_score_path(@course, lessons(:advanced), @answer), params: { question_answer: { ai_score: 8 } }
    assert_response :not_found
    get report_course_lesson_path(@course, lessons(:physics_lesson))
    assert_response :not_found
  end

  test "non-owners cannot access reports or score answers by direct request" do
    [ :other_instructor, :student ].each do |role|
      sign_in users(role)
      get report_course_path(@course)
      assert_redirected_to root_path
      get report_course_lesson_path(@course, @lesson)
      assert_redirected_to root_path
      patch score_path, params: { question_answer: { ai_score: 10 } }
      assert_redirected_to root_path
      assert_nil @answer.reload.ai_score
      sign_out users(role)
    end

    sign_in users(:student)
    get marking_queue_path
    assert_redirected_to root_path
  end

  test "guests must sign in for reports queue and scoring" do
    [ report_course_path(@course), report_course_lesson_path(@course, @lesson), marking_queue_path ].each do |path|
      get path
      assert_redirected_to new_user_session_path
    end
    patch score_path, params: { question_answer: { ai_score: 10 } }
    assert_redirected_to new_user_session_path
    assert_nil @answer.reload.ai_score
  end

  test "marking queue lets the owner score answers inline and returns to the queue" do
    sign_in users(:instructor)

    get marking_queue_path
    assert_response :success
    assert_match @answer.answer_text, response.body
    assert_match questions(:intro_q1).prompt, response.body
    assert_select "form[action=?]", score_path do
      assert_select "input[name=return_to][value=?]", marking_queue_path
      assert_select "button[name='question_answer[ai_score]']", count: 10
    end

    patch score_path, params: { question_answer: { ai_score: 8 }, return_to: marking_queue_path(lesson: @lesson.id) }
    assert_redirected_to marking_queue_path(lesson: @lesson.id)
    assert_equal 8, @answer.reload.ai_score
  end

  test "scoring ignores return paths outside the marking queue" do
    sign_in users(:instructor)
    [ "https://evil.example/marking_queue", "//evil.example", "/admin/marking_queue", "/marking_queue_evil" ].each do |return_to|
      @answer.update_columns(ai_score: nil, scored_at: nil)
      patch score_path, params: { question_answer: { ai_score: 8 }, return_to: return_to }
      assert_redirected_to report_course_lesson_path(@course, @lesson)
    end
  end

  test "marking queue can be filtered to one lesson" do
    sign_in users(:instructor)
    get marking_queue_path(lesson: @lesson.id)
    assert_response :success
    assert_select "#marking-lesson-#{@lesson.id}"
    assert_select "input[name=return_to][value=?]", marking_queue_path(lesson: @lesson.id)
  end

  test "home page alerts instructors with answers to mark" do
    sign_in users(:instructor)
    get root_path
    assert_select "[role=status] a[href=?]", marking_queue_path
    assert_match "1 answer is waiting for you to mark", response.body

    @lesson.update!(cbai_api_key: "test-key")
    get root_path
    assert_select "[role=status] a[href=?]", marking_queue_path, count: 0
    sign_out users(:instructor)

    sign_in users(:other_instructor)
    @lesson.update!(cbai_api_key: nil)
    get root_path
    assert_select "[role=status] a[href=?]", marking_queue_path, count: 0
  end

  test "lesson report links to the marking queue for pending manual answers" do
    sign_in users(:instructor)
    get report_course_lesson_path(@course, @lesson)
    assert_select "[role=status] a[href=?]", marking_queue_path(lesson: @lesson.id)
  end

  test "question report filters, searches and paginates answers" do
    users = 30.times.map { |i| User.create!(email: "learner#{i}@example.com", name: "Learner #{i}", password: "Password123!") }
    users.each_with_index do |user, i|
      enrollment = Enrollment.create!(user: user, course: @course)
      QuestionAnswer.create!(enrollment: enrollment, question: questions(:intro_q1), answer_text: "Answer #{i}", ai_score: (i < 5 ? 9 : nil))
    end
    sign_in users(:instructor)

    get question_path
    assert_response :success
    assert_select "li[id^=answer-]", 25
    assert_select "form[action$='/score']", 25

    get question_path(page: 2)
    assert_select "li[id^=answer-]", 1

    get question_path(page: 9)
    assert_redirected_to question_path(page: 2)

    get question_path(status: "passed")
    assert_select "li[id^=answer-]", 5
    assert_select "form[action$='/score']", 0

    get question_path(status: "all", q: "learner7@")
    assert_select "li[id^=answer-]", 1
    assert_match "Answer 7", response.body

    get question_path(status: "all", q: "%")
    assert_select "li[id^=answer-]", 0
  end

  test "scoring from the question report returns to it" do
    sign_in users(:instructor)
    return_to = question_path(status: "pending", page: 1)
    patch score_path, params: { question_answer: { ai_score: 4 }, return_to: return_to }
    assert_redirected_to return_to

    other = course_lesson_question_answer_score_path(@course, @lesson, QuestionAnswer.find_by!(question: questions(:intro_q2)))
    questions(:intro_q2).update!(kind: :free_text)
    patch other, params: { question_answer: { ai_score: 4 }, return_to: return_to }
    assert_redirected_to report_course_lesson_path(@course, @lesson)
  end

  test "question report is limited to the owner and free-text questions" do
    sign_in users(:other_instructor)
    get question_path
    assert_redirected_to root_path
    sign_out users(:other_instructor)

    sign_in users(:instructor)
    questions(:intro_q1).update!(kind: :multiple_choice)
    get question_path
    assert_response :not_found
  end

  test "marking queue shows a capped batch of the oldest pending answers" do
    users = 25.times.map { |i| User.create!(email: "queued#{i}@example.com", name: "Queued #{i}", password: "Password123!") }
    users.each_with_index do |user, i|
      enrollment = Enrollment.create!(user: user, course: @course)
      QuestionAnswer.create!(enrollment: enrollment, question: questions(:intro_q1), answer_text: "Queued answer #{i}")
    end
    sign_in users(:instructor)

    get marking_queue_path(lesson: @lesson.id)
    assert_response :success
    assert_select "li[id^=answer-]", MarkingWorkspace::ANSWERS_PER_LESSON
    assert_match "Showing the oldest 20 of 26", response.body
    assert_match @answer.answer_text, response.body
  end

  test "instructors still cannot enter admin" do
    sign_in users(:instructor)
    get admin_root_path
    assert_redirected_to root_path
    patch admin_question_answer_score_path(@answer), params: { question_answer: { ai_score: 10 } }
    assert_redirected_to root_path
    assert_nil @answer.reload.ai_score
  end

  private

  def score_path
    course_lesson_question_answer_score_path(@course, @lesson, @answer)
  end

  def question_path(**query)
    question_report_course_lesson_path(@course, @lesson, questions(:intro_q1), **query)
  end
end
