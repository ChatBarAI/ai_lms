require "test_helper"

class SequentialLessonsTest < ActionDispatch::IntegrationTest
  setup do
    @course = courses(:algebra)
    @course.update!(sequential_lessons: true)
    @intro = lessons(:intro)
    @advanced = lessons(:advanced)
    @locked_message = I18n.t("lessons.locked.message", title: @intro.title, lesson_l: Lesson.model_name.human.downcase)
  end

  test "a learner cannot open a lesson before completing the earlier ones" do
    sign_in users(:student)

    get course_lesson_path(@course, @advanced)

    assert_redirected_to course_path(@course)
    assert_equal @locked_message, flash[:alert]
    assert_nil enrollments(:student_in_algebra).progresses.find_by(lesson: @advanced)
  end

  test "a learner cannot start or submit a locked lesson by posting directly" do
    sign_in users(:student)

    assert_no_difference [ "Progress.count", "QuestionAnswer.count" ] do
      post start_course_lesson_path(@course, @advanced)
      assert_redirected_to course_path(@course)
      post submit_quiz_course_lesson_path(@course, @advanced), params: { answers: { questions(:intro_q_free).id => "Anything" } }
      assert_redirected_to course_path(@course)
    end
  end

  test "a learner cannot reach the materials of a locked lesson" do
    material = LessonMaterial.create!(lesson: @advanced, title: "Pre-read", kind: :html, body: "<p>read</p>", required: true)
    sign_in users(:student)

    assert_no_difference "LessonMaterialAcknowledgement.count" do
      post acknowledge_course_lesson_lesson_material_path(@course, @advanced, material)
    end
    assert_redirected_to course_path(@course)

    get course_lesson_lesson_material_path(@course, @advanced, material)
    assert_redirected_to course_path(@course)
  end

  test "the lesson unlocks once the earlier lesson is complete" do
    progresses(:student_intro).update!(status: :completed)
    sign_in users(:student)

    get course_lesson_path(@course, @advanced)

    assert_response :success
  end

  test "guests can open only the first lesson" do
    get course_lesson_path(@course, @intro)
    assert_response :success

    get course_lesson_path(@course, @advanced)
    assert_redirected_to course_path(@course)
  end

  test "the owner can preview every lesson" do
    sign_in users(:instructor)

    get course_lesson_path(@course, @advanced)

    assert_response :success
  end

  test "locked lessons show a padlock and open the locked dialog on the course page and in the sidebar" do
    sign_in users(:student)
    locked_link = "a[href=?][data-controller='status-modal'][data-status-modal-link-url-param=?]"

    get course_path(@course)
    assert_response :success
    assert_select "a[href=?]:not([data-controller])", course_lesson_path(@course, @intro)
    assert_select locked_link, course_lesson_path(@course, @advanced), course_lesson_path(@course, @intro)
    assert_select "svg[aria-label=?]", I18n.t("lessons.locked.label")
    assert_select "#locked-lesson-dialog[role=dialog].hidden"

    get course_lesson_path(@course, @intro)
    assert_response :success
    assert_select "#lesson-course-sidebar #{locked_link}", course_lesson_path(@course, @advanced), course_lesson_path(@course, @intro)
    assert_select "#lesson-course-sidebar svg[aria-label=?]", I18n.t("lessons.locked.label")
    assert_select "#locked-lesson-dialog [data-dialog-fill=link]"
  end

  test "no locked dialog is rendered once every lesson is open" do
    progresses(:student_intro).update!(status: :completed)
    sign_in users(:student)

    get course_path(@course)

    assert_select "#locked-lesson-dialog", count: 0
    assert_select "a[data-status-modal-dialog-id-value='locked-lesson-dialog']", count: 0
  end

  test "nothing is locked when the course setting is off" do
    @course.update!(sequential_lessons: false)
    sign_in users(:student)

    get course_lesson_path(@course, @advanced)

    assert_response :success
  end

  test "the owner can turn the setting on from the course form" do
    @course.update!(sequential_lessons: false)
    sign_in users(:instructor)

    get edit_course_path(@course)
    assert_select "input[type=checkbox][name=?]", "course[sequential_lessons]"

    patch course_path(@course), params: { course: { sequential_lessons: "1" } }

    assert_redirected_to @course
    assert @course.reload.sequential_lessons?
  end
end
