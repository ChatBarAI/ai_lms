require "test_helper"

class TerminologyControllerTest < ActionDispatch::IntegrationTest
  setup do
    @setting = SiteSetting.current
    @original_terminology = @setting.terminology.deep_dup
    @setting.update!(terminology: {
      "en" => { "course_one" => "Module", "course_other" => "Modules", "lesson_one" => "Activity", "lesson_other" => "Activities" },
      "de" => { "course_one" => "Baustein", "course_other" => "Bausteine", "lesson_one" => "Einheit", "lesson_other" => "Einheiten" }
    })
    @course = courses(:algebra)
    @lesson = lessons(:intro)
  end

  teardown do
    @setting.update!(terminology: @original_terminology)
    TerminologyApplier.call
  end

  test "authoring headings and navigation use both configured model names" do
    sign_in users(:instructor)

    get edit_course_path(@course)
    assert_response :success
    assert_select "h1", text: "Edit Module · Algebra"
    assert_select "a", text: "Add activity"

    get new_course_path
    assert_response :success
    assert_select "h1", text: "New module"

    get new_course_lesson_path(@course)
    assert_response :success
    assert_select "h1", text: "New activity"
    assert_select "label", text: "Activity description"

    get edit_course_lesson_path(@course, @lesson)
    assert_response :success
    assert_select "a", text: "← View activity"

    get video_upload_course_lesson_path(@course, @lesson)
    assert_response :success
    assert_select "a", text: "← Back to activity edit"
  end

  test "learner navigation accessibility and completion confirmation use terminology" do
    @lesson.questions.destroy_all
    sign_in users(:student)

    get course_lesson_path(@course, @lesson)
    assert_response :success
    assert_select "a", text: "← Module"
    assert_select "nav[aria-label=?]", "Activities in this module"
    assert_select "button[aria-label=?]", "Close module contents"
    assert_select "input[data-turbo-confirm=?]", "Mark this activity as completed?"

    progresses(:student_intro).update!(status: :completed)
    get course_lesson_path(@course, @lesson)
    assert_response :success
    assert_select "h3", text: "Rate this activity"
  end

  test "admin lists reports and dashboard use configured singular and plural names" do
    sign_in users(:admin)

    get admin_course_lessons_path(@course)
    assert_response :success
    assert_select "title", text: /Activities — Algebra/
    assert_select "h1", text: "Activities"
    assert_select "a", text: "Add activity"

    get report_admin_course_path(@course)
    assert_response :success
    assert_select "th", text: "Activity"
    assert_select "a", text: "Back to module"

    get admin_marking_queue_path
    assert_response :success
    assert_select "h1", text: "Activities needing marking"

    get admin_root_path
    assert_response :success
    assert_includes response.body, "Modules · Activities"
  end

  test "copy dialog sends translated prompts to JavaScript in each user locale" do
    LessonMaterial.create!(lesson: @lesson, title: "Copy source", kind: :html, body: "<p>Read this</p>")
    instructor = users(:instructor)

    {
      "en" => [ "Module", "Activity", "Choose module…", "Choose activity…" ],
      "de" => [ "Baustein", "Einheit", "Baustein auswählen…", "Einheit auswählen…" ]
    }.each do |locale, (course_label, lesson_label, course_prompt, lesson_prompt)|
      instructor.update!(locale: locale)
      sign_in instructor
      get new_course_lesson_lesson_material_path(@course, @lesson)

      assert_response :success
      assert_select "label[for=source_course_id]", text: course_label
      assert_select "label[for=source_lesson_id]", text: lesson_label
      assert_select "select#source_course_id option[value='']", text: course_prompt
      assert_select "[data-controller='material-copy-selector']" do |elements|
        prompts = JSON.parse(elements.first["data-material-copy-selector-prompts-value"])
        assert_equal lesson_prompt, prompts.fetch("lesson")
        assert_includes prompts.fetch("courseFirst").downcase, course_label.downcase
        assert_includes prompts.fetch("lessonFirst").downcase, lesson_label.downcase
      end
      sign_out instructor
    end
  end

  test "flash messages and German UI use locale-specific overrides" do
    instructor = users(:instructor)
    instructor.update!(locale: "de")
    sign_in instructor

    get edit_course_lesson_path(@course, @lesson)
    assert_response :success
    assert_select "label", text: "Einheit: Beschreibung"
    assert_select "a", text: "← Einheit ansehen"

    patch course_lesson_path(@course, @lesson), params: { lesson: { title: @lesson.title } }
    assert_redirected_to course_lesson_path(@course, @lesson)
    assert_equal "Einheit aktualisiert.", flash[:notice]

    post publish_course_path(@course)
    assert_redirected_to course_path(@course)
    assert_equal "Baustein veröffentlicht.", flash[:notice]
  end

  test "prerequisite validation uses the configured plural name" do
    CoursePrerequisite.create!(course: courses(:other_owner_course), prerequisite_course: @course)
    enrollment = Enrollment.new(user: users(:other_student), course: courses(:other_owner_course))

    assert_not enrollment.valid?
    assert_includes enrollment.errors[:base], "Complete these modules first: Algebra"
  end

  test "manifest shortcut preserves quotes and follows the current locale" do
    @setting.update!(terminology: @setting.terminology.deep_merge("de" => { "course_other" => 'Bausteine "Plus"' }))
    student = users(:student)
    student.update!(locale: "de")
    sign_in student

    get pwa_manifest_path

    assert_response :success
    manifest = JSON.parse(response.body)
    assert_equal "de", manifest.fetch("lang")
    assert_equal 'Bausteine "Plus" durchsuchen', manifest.fetch("shortcuts").first.fetch("name")
    assert_equal 'Bausteine "Plus"', manifest.fetch("shortcuts").first.fetch("short_name")
    assert_includes response.headers["Cache-Control"], "private"
  end
end
