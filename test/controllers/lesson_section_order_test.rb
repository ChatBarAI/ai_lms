require "test_helper"

class LessonSectionOrderTest < ActionDispatch::IntegrationTest
  setup do
    @lesson = lessons(:intro)
    @course = courses(:algebra)
    @order = %w[progress introduction materials quiz_results quiz rating ai_tutor]
  end

  test "owner saves a section order for only the selected lesson" do
    sign_in users(:instructor)

    patch course_lesson_path(@course, @lesson), params: { lesson: { section_order: @order } }

    assert_redirected_to course_lesson_path(@course, @lesson)
    assert_equal @order, @lesson.reload.section_order
    assert_equal [], lessons(:advanced).section_order

    get edit_course_lesson_path(@course, @lesson)
    assert_response :success
    assert_select "input[name='lesson[section_order][]']" do |inputs|
      assert_equal @order, inputs.map { |input| input["value"] }
    end
    assert_select "[data-controller='lesson-section-order'] button[type='button']", count: 15
    assert_no_match "translation_missing", response.body
  end

  test "owner creates a lesson with a custom section order" do
    sign_in users(:instructor)

    assert_difference("Lesson.count", 1) do
      post course_lessons_path(@course), params: { lesson: { title: "Custom layout", section_order: @order } }
    end

    created = Lesson.order(:id).last
    assert_redirected_to course_lesson_path(@course, created)
    assert_equal @order, created.section_order
  end

  test "unrelated edits preserve the saved section order" do
    @lesson.update!(section_order: @order)
    sign_in users(:instructor)

    patch course_lesson_path(@course, @lesson), params: { lesson: { title: "Renamed" } }

    assert_redirected_to course_lesson_path(@course, @lesson)
    assert_equal @order, @lesson.reload.section_order
  end

  test "invalid section order is rejected without replacing the saved layout" do
    @lesson.update!(section_order: @order)
    sign_in users(:instructor)

    [ %w[progress progress], [ "../admin/users" ] ].each do |invalid_order|
      patch course_lesson_path(@course, @lesson), params: { lesson: { section_order: invalid_order } }

      assert_response :unprocessable_entity
      assert_equal @order, @lesson.reload.section_order
    end
  end

  test "validation errors preserve the submitted order in the edit form" do
    sign_in users(:instructor)

    patch course_lesson_path(@course, @lesson), params: { lesson: { title: "", section_order: @order } }

    assert_response :unprocessable_entity
    assert_equal [], @lesson.reload.section_order
    assert_select "input[name='lesson[section_order][]']" do |inputs|
      assert_equal @order, inputs.map { |input| input["value"] }
    end
  end

  test "students and other course owners cannot change the section order" do
    [ users(:student), users(:other_instructor) ].each do |user|
      sign_in user
      patch course_lesson_path(@course, @lesson), params: { lesson: { section_order: @order } }

      assert_redirected_to root_path
      assert_equal [], @lesson.reload.section_order
      sign_out user
    end
  end

  test "default layout preserves the original order of all visible sections" do
    complete_lesson_with_optional_material

    get course_lesson_path(@course, @lesson)

    assert_response :success
    assert_section_order %w[introduction ai_tutor materials progress quiz_results quiz rating]
    assert_no_match "translation_missing", response.body
  end

  test "custom layout moves progress and tutor without moving detailed feedback with progress" do
    @lesson.update!(section_order: @order)
    complete_lesson_with_optional_material

    get course_lesson_path(@course, @lesson)

    assert_response :success
    assert_section_order @order
    assert_select "#lesson-status #quiz-results", count: 0
    assert_select "#quiz-results h2", text: "Quiz answer feedback"
  end

  test "custom layout retains section visibility for guests and unenrolled users" do
    @lesson.update!(section_order: @order, cbai_display_mode: "none")

    get course_lesson_path(@course, @lesson)

    assert_response :success
    assert_section_order %w[introduction quiz]

    sign_in users(:instructor)
    get course_lesson_path(@course, @lesson)

    assert_response :success
    assert_section_order %w[introduction quiz]
    assert_select "form[action=?]", course_enrollments_path(@course)
  end

  test "quiz before materials remains locked until required materials are completed" do
    @lesson.update!(section_order: %w[quiz materials])
    material = @lesson.lesson_materials.create!(title: "Required reading", kind: :html, body: "Read this", required: true)
    sign_in users(:student)

    get course_lesson_path(@course, @lesson)

    assert_response :success
    assert_select "#lesson-quiz a[href='#lesson-materials']", text: "View required materials"
    assert_select "#lesson-quiz form", count: 0

    assert_no_difference("QuestionAnswer.count") do
      post submit_quiz_course_lesson_path(@course, @lesson), params: { answers: { questions(:intro_q1).id.to_s => "2" } }
    end
    assert_redirected_to course_lesson_path(@course, @lesson)
    assert_equal I18n.t("lessons.flash.complete_required_materials"), flash[:alert]

    LessonMaterialAcknowledgement.create!(enrollment: enrollments(:student_in_algebra), lesson_material: material)
    get course_lesson_path(@course, @lesson)

    assert_response :success
    assert_select "#lesson-quiz form[action=?]", submit_quiz_course_lesson_path(@course, @lesson)
    assert_select "#lesson-quiz a[href='#lesson-materials']", count: 0
  end

  private

  def complete_lesson_with_optional_material
    @lesson.lesson_materials.create!(title: "Reading", kind: :html, body: "Read this", required: false)
    sign_in users(:student)
    post submit_quiz_course_lesson_path(@course, @lesson), params: {
      answers: { questions(:intro_q1).id.to_s => "2", questions(:intro_q2).id.to_s => "4" }
    }
    assert_redirected_to course_lesson_path(@course, @lesson, anchor: "lesson-status")
  end

  def assert_section_order(expected)
    ids = {
      "introduction" => "lesson-introduction",
      "ai_tutor" => "cbai_launcher_#{@lesson.id}",
      "materials" => "lesson-materials",
      "progress" => "lesson-status",
      "quiz_results" => "quiz-results",
      "quiz" => "lesson-quiz",
      "rating" => "lesson-rating"
    }
    selector = ids.values.map { |id| "##{id}" }.join(", ")
    assert_select selector do |sections|
      assert_equal expected, sections.map { |section| ids.key(section["id"]) }
    end
  end
end
