require "test_helper"

class CoursePrerequisiteLockTest < ActionDispatch::IntegrationTest
  setup do
    @algebra = courses(:algebra)
    @physics = courses(:other_owner_course)
    CoursePrerequisite.create!(course: @physics, prerequisite_course: @algebra)
    @locked_link = "a[href=?][data-controller='status-modal'][data-status-modal-link-url-param=?]"
  end

  test "a module with unmet prerequisites shows a padlock that opens the locked dialog" do
    sign_in users(:student)

    get courses_path

    assert_response :success
    assert_select @locked_link, course_path(@physics), course_path(@algebra)
    assert_select "a[href=?][data-status-modal-message-param*=?]", course_path(@physics), "“#{@algebra.title}”"
    assert_select "a[href=?] svg[aria-label=?]", course_path(@physics), I18n.t("locked.label")
    assert_select "a[href=?][data-controller]", course_path(@algebra), count: 0
    assert_select "#locked-dialog[role=dialog].hidden"
    assert_select "p", text: /Requires:/, count: 0
  end

  test "completing the prerequisite unlocks the module card" do
    enrollment = enrollments(:student_in_algebra)
    @algebra.lessons_required_for_completion.each do |lesson|
      enrollment.progresses.find_or_initialize_by(lesson: lesson).update!(status: :completed)
    end
    sign_in users(:student)

    get courses_path

    assert_select "a[href=?][data-controller]", course_path(@physics), count: 0
    assert_select "#locked-dialog", count: 0
  end

  test "learners already enrolled and the module owner are not locked out" do
    Enrollment.new(user: users(:other_student), course: @physics, skip_prerequisite_check: true).save!
    sign_in users(:other_student)
    get courses_path
    assert_select "a[href=?][data-controller]", course_path(@physics), count: 0

    sign_out users(:other_student)
    sign_in users(:other_instructor)
    get courses_path
    assert_select "a[href=?][data-controller]", course_path(@physics), count: 0
  end

  test "the module page shows a padlock and Enrol now opens the locked dialog" do
    sign_in users(:student)

    get course_path(@physics)

    assert_response :success
    assert_select "h1 button[data-controller='status-modal'][data-status-modal-link-url-param=?] svg[aria-label=?]", course_path(@algebra), I18n.t("locked.label")
    assert_select "form[action=?][data-action='submit->status-modal#open'][data-status-modal-dialog-id-value='locked-dialog']", course_enrollments_path(@physics)
    assert_select "#locked-dialog[role=dialog]", count: 1
  end

  test "a module with met prerequisites has no padlock and enrols normally" do
    sign_in users(:other_student)

    get course_path(@algebra)

    assert_select "h1 button[data-controller]", count: 0
    assert_select "form[action=?]:not([data-action])", course_enrollments_path(@algebra), count: 1
    assert_select "#locked-dialog", count: 0
  end

  test "Buy opens the prerequisite dialog instead of submitting checkout" do
    @physics.update!(access_policy: "entitlement_required", price_minor: 1000, price_currency: "eur")
    sign_in users(:student)

    Payments::Configuration.stub(:checkout_ready?, true) do
      get course_path(@physics)
    end

    assert_response :success
    assert_select "form[action=?][method=post][data-turbo=false][data-controller='status-modal'][data-action='submit->status-modal#open'][data-status-modal-dialog-id-value='locked-dialog']", course_purchases_path(@physics), count: 1 do
      assert_select "button[type=submit][aria-haspopup=dialog][aria-controls='locked-dialog']", text: I18n.t("payments.buy")
    end
    assert_select "form[action=?][data-status-modal-link-url-param=?][data-status-modal-message-param=?]", course_purchases_path(@physics), course_path(@algebra),
                  I18n.t("locked.course_message", titles: "“#{@algebra.title}”", course_l: Course.model_name.human.downcase)
    assert_select "#locked-dialog[role=dialog].hidden", count: 1
  end

  test "Buy submits normally once prerequisites are complete" do
    @physics.update!(access_policy: "entitlement_required", price_minor: 1000, price_currency: "eur")
    @algebra.lessons_required_for_completion.each do |lesson|
      enrollments(:student_in_algebra).progresses.find_or_initialize_by(lesson: lesson).update!(status: :completed)
    end
    sign_in users(:student)

    Payments::Configuration.stub(:checkout_ready?, true) do
      get course_path(@physics)
    end

    assert_response :success
    assert_select "form[action=?][method=post][data-turbo=false]:not([data-action]):not([data-controller])", course_purchases_path(@physics), count: 1 do
      assert_select "button[type=submit]:not([aria-haspopup]):not([aria-controls])", text: I18n.t("payments.buy")
    end
    assert_select "#locked-dialog", count: 0
  end

  test "lesson cards outside the module page show their lock" do
    @algebra.update!(sequential_lessons: true)
    tag = Tag.create!(name: "Locks", color: "#3b82f6")
    lessons(:intro).tags << tag
    lessons(:advanced).tags << tag
    sign_in users(:student)

    get tag_path(tag)

    assert_response :success
    assert_select "a[href=?][data-status-modal-link-url-param=?]", course_lesson_path(@algebra, lessons(:advanced)), course_lesson_path(@algebra, lessons(:intro))
    assert_select "a[href=?]:not([data-controller])", course_lesson_path(@algebra, lessons(:intro))
    assert_select "#locked-dialog", count: 1
  end

  test "the module card dialog offers to view the module" do
    sign_in users(:student)

    get courses_path

    assert_select "a[href=?][data-status-modal-secondary-url-param=?]", course_path(@physics), course_path(@physics)
    assert_select "#locked-dialog a.hidden[data-dialog-fill='secondary-link']"
  end

  test "every lesson in a module with unmet prerequisites is locked" do
    lesson = lessons(:physics_lesson)
    message = I18n.t("locked.course_message", titles: "“#{@algebra.title}”", course_l: Course.model_name.human.downcase)
    sign_in users(:student)

    get course_lesson_path(@physics, lesson)
    assert_redirected_to course_path(@physics)
    assert_equal message, flash[:alert]

    assert_no_difference "Progress.count" do
      post start_course_lesson_path(@physics, lesson)
    end
    assert_redirected_to course_path(@physics)

    get course_path(@physics)
    assert_select "a[href=?][data-status-modal-link-url-param=?]", course_lesson_path(@physics, lesson), course_path(@algebra)
    assert_select "a[href=?][data-status-modal-secondary-url-param]", course_lesson_path(@physics, lesson), count: 0
  end

  # Deliberate: a guest gets no more access than a signed-in learner who has not
  # met the prerequisites, so public access does not bypass the gate.
  test "guests are locked out of a public module's lessons until they sign in and meet its prerequisites" do
    @physics.update!(public_access_enabled: true, access_policy: "free")
    lesson = lessons(:physics_lesson)

    get course_lesson_path(@physics, lesson)

    assert_redirected_to course_path(@physics)
    assert_equal I18n.t("locked.course_message_guest", titles: "“#{@algebra.title}”", course_l: Course.model_name.human.downcase), flash[:alert]

    follow_redirect!
    assert_select "h1 button[data-status-modal-link-url-param=?][data-status-modal-link-label-param=?]", new_user_session_path, I18n.t("locked.sign_in")
    assert_select "a[href=?][data-status-modal-link-url-param=?]", course_lesson_path(@physics, lesson), new_user_session_path
  end

  test "a guest's module card dialog offers sign in" do
    @physics.update!(public_access_enabled: true, access_policy: "free")
    @algebra.update!(public_access_enabled: true, access_policy: "free")

    get courses_path

    assert_select "a[href=?][data-status-modal-link-url-param=?][data-status-modal-message-param=?]", course_path(@physics), new_user_session_path,
                  I18n.t("locked.course_message_guest", titles: "“#{@algebra.title}”", course_l: Course.model_name.human.downcase)
  end

  [ :guest, :student ].each do |viewer|
    [ :index, :show, :document ].each do |action|
      test "#{viewer} cannot access material #{action} with unmet module prerequisites" do
        @physics.update!(public_access_enabled: true, access_policy: "free")
        lesson = lessons(:physics_lesson)
        material = LessonMaterial.create!(lesson: lesson, title: "Locked document", kind: :raw_html_iframe,
          raw_html_content: "<p>Prerequisite-protected content</p>")
        sign_in users(:student) if viewer == :student
        path = case action
        when :index then course_lesson_lesson_materials_path(@physics, lesson)
        when :show then course_lesson_lesson_material_path(@physics, lesson, material)
        when :document then document_course_lesson_lesson_material_path(@physics, lesson, material)
        end

        get path

        assert_redirected_to course_path(@physics)
        key = viewer == :guest ? "locked.course_message_guest" : "locked.course_message"
        assert_equal I18n.t(key, titles: "“#{@algebra.title}”", course_l: Course.model_name.human.downcase), flash[:alert]
        assert_not_includes response.body, "Prerequisite-protected content"
      end
    end
  end

  [ :html, :json ].each do |format|
    test "material acknowledgement in #{format} is blocked by unmet module prerequisites without recording progress" do
      lesson = lessons(:physics_lesson)
      material = LessonMaterial.create!(lesson: lesson, title: "Locked reading", kind: :html,
        body: "<p>Read this</p>", required: true)
      sign_in users(:student)
      message = I18n.t("locked.course_message", titles: "“#{@algebra.title}”", course_l: Course.model_name.human.downcase)

      assert_no_difference [ "LessonMaterialAcknowledgement.count", "Progress.count" ] do
        post acknowledge_course_lesson_lesson_material_path(@physics, lesson, material), as: format
      end

      if format == :json
        assert_response :forbidden
        assert_equal message, response.parsed_body["error"]
      else
        assert_redirected_to course_path(@physics)
        assert_equal message, flash[:alert]
      end
    end
  end

  test "lessons in a gated module stay open to enrolled learners and the owner" do
    lesson = lessons(:physics_lesson)
    Enrollment.new(user: users(:other_student), course: @physics, skip_prerequisite_check: true).save!
    sign_in users(:other_student)
    get course_lesson_path(@physics, lesson)
    assert_response :success

    sign_out users(:other_student)
    sign_in users(:other_instructor)
    get course_lesson_path(@physics, lesson)
    assert_response :success
  end
end
