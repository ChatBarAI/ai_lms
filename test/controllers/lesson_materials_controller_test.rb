require "test_helper"

class LessonMaterialsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @course  = courses(:algebra)
    @lesson  = lessons(:intro)
    @material = LessonMaterial.create!(lesson: @lesson, title: "Pre-read", kind: :html,
                                       body: "<p>read this</p>", required: true)
  end

  # ---------------------------------------------------------------------------
  # Guest (unauthenticated)
  # ---------------------------------------------------------------------------

  test "guest can view index of materials on a published lesson" do
    get course_lesson_lesson_materials_path(@course, @lesson)
    assert_response :success
  end

  test "guest can view a published material" do
    get course_lesson_lesson_material_path(@course, @lesson, @material)
    assert_response :success
    assert_select "#material-#{@material.id}[data-expanded='true']"
  end

  test "guest sees a youtube video URL material as an iframe" do
    material = LessonMaterial.create!(
      lesson: @lesson,
      title: "YouTube clip",
      kind: :video_url,
      url: "https://youtu.be/Hla6u6WpRE0?si=OEhPSA0s1EZog4ws"
    )

    get course_lesson_lesson_material_path(@course, @lesson, material)

    assert_response :success
    assert_select "iframe[src^='https://www.youtube.com/embed/Hla6u6WpRE0']", count: 1
    assert_select "video", count: 0
  end

  test "guest can view a published Google document with restrictive headers" do
    material = LessonMaterial.create!(
      lesson: @lesson,
      title: "Imported document",
      kind: :google_doc,
      raw_html_content: "<!doctype html><html><body><p>Hello</p></body></html>"
    )

    get document_course_lesson_lesson_material_path(@course, @lesson, material)

    assert_response :success
    assert_equal "text/html", response.media_type
    assert_includes response.headers["Content-Security-Policy"], "script-src 'none'"
    assert_includes response.headers["Content-Security-Policy"], "media-src 'self'"
    assert_includes response.headers["Content-Security-Policy"], "frame-ancestors 'self'"
    assert_nil response.headers["X-Frame-Options"]
    assert_includes response.body, "<p>Hello</p>"
  end

  test "guest can view published isolated raw HTML through the document endpoint" do
    material = LessonMaterial.create!(
      lesson: @lesson,
      title: "Isolated document",
      kind: :raw_html_iframe,
      raw_html_content: "<style>.card { color: red; }</style><p class=\"card\">Hello</p>"
    )

    get document_course_lesson_lesson_material_path(@course, @lesson, material)

    assert_response :success
    assert_includes response.headers["Content-Security-Policy"], "script-src 'none'"
    assert_includes response.body, ".card { color: red; }"
    assert_includes response.body, '<p class="card">Hello</p>'
  end

  test "guest can view a published web-page snapshot through the document endpoint" do
    material = LessonMaterial.create!(
      lesson: @lesson,
      title: "Web snapshot",
      kind: :web_page,
      url: "https://example.com/article",
      raw_html_content: "<!doctype html><html><body><p>Snapshot</p></body></html>"
    )

    get document_course_lesson_lesson_material_path(@course, @lesson, material)

    assert_response :success
    assert_includes response.headers["Content-Security-Policy"], "connect-src 'none'"
    assert_includes response.body, "<p>Snapshot</p>"
  end

  test "guest is redirected to sign-in when creating" do
    post course_lesson_lesson_materials_path(@course, @lesson),
         params: { lesson_material: { title: "X", kind: "html", body: "x" } }
    assert_redirected_to new_user_session_path
  end

  test "guest is redirected to sign-in when updating" do
    patch course_lesson_lesson_material_path(@course, @lesson, @material),
          params: { lesson_material: { title: "Hacked" } }
    assert_redirected_to new_user_session_path
  end

  test "guest is redirected to sign-in when destroying" do
    delete course_lesson_lesson_material_path(@course, @lesson, @material)
    assert_redirected_to new_user_session_path
  end

  test "guest is redirected to sign-in when acknowledging" do
    post acknowledge_course_lesson_lesson_material_path(@course, @lesson, @material)
    assert_redirected_to new_user_session_path
  end

  test "guest is redirected to sign-in when reordering" do
    post reorder_course_lesson_lesson_materials_path(@course, @lesson),
         params: { ids: [ @material.id ] }
    assert_redirected_to new_user_session_path
  end

  # ---------------------------------------------------------------------------
  # Enrolled student — read-only, no mutation
  # ---------------------------------------------------------------------------

  test "enrolled student can view a published material" do
    sign_in users(:student)
    get course_lesson_lesson_material_path(@course, @lesson, @material)
    assert_response :success
  end

  test "enrolled student cannot create a material" do
    sign_in users(:student)
    post course_lesson_lesson_materials_path(@course, @lesson),
         params: { lesson_material: { title: "X", kind: "html", body: "x" } }
    assert_redirected_to root_path
  end

  test "enrolled student cannot update a material" do
    sign_in users(:student)
    patch course_lesson_lesson_material_path(@course, @lesson, @material),
          params: { lesson_material: { title: "Hacked" } }
    assert_redirected_to root_path
  end

  test "enrolled student cannot destroy a material" do
    sign_in users(:student)
    delete course_lesson_lesson_material_path(@course, @lesson, @material)
    assert_redirected_to root_path
  end

  test "enrolled student cannot reorder materials" do
    sign_in users(:student)
    post reorder_course_lesson_lesson_materials_path(@course, @lesson),
         params: { ids: [ @material.id ] }
    assert_redirected_to root_path
  end

  test "student cannot view material on a draft lesson" do
    draft_material = LessonMaterial.create!(lesson: lessons(:draft_lesson), title: "Draft R",
                                            kind: :html, body: "x")
    sign_in users(:student)
    get course_lesson_lesson_material_path(@course, lessons(:draft_lesson), draft_material)
    assert_redirected_to root_path
  end

  # ---------------------------------------------------------------------------
  # Unenrolled student
  # ---------------------------------------------------------------------------

  test "unenrolled student is redirected with alert when acknowledging" do
    sign_in users(:other_student)
    post acknowledge_course_lesson_lesson_material_path(@course, @lesson, @material)
    assert_redirected_to course_lesson_path(@course, @lesson)
    follow_redirect!
    assert_match "Enrol", flash[:alert].to_s
  end

  # ---------------------------------------------------------------------------
  # Owner instructor — full CRUD
  # ---------------------------------------------------------------------------

  test "instructor can get new material form" do
    sign_in users(:instructor)
    get new_course_lesson_lesson_material_path(@course, @lesson)
    assert_response :success
  end

  test "material form submits without turbo so validation errors stay visible" do
    sign_in users(:instructor)
    get new_course_lesson_lesson_material_path(@course, @lesson)

    assert_response :success
    assert_select "form[data-turbo=?]", "false"
    assert_select "form[data-action*='submit->material-kind']", count: 0
  end

  test "new material form offers the AI designer as a kind instead of a separate action" do
    sign_in users(:instructor)
    get new_course_lesson_lesson_material_path(@course, @lesson)

    assert_select 'select[name="lesson_material[kind]"] option[value="ai_designed"]', text: "AI-designed page"
    assert_select 'input[type="submit"][name="start_ai_design"]', count: 0
  end

  test "new material form offers copying as a kind and opens its source in a dialog" do
    sign_in users(:instructor)
    get new_course_lesson_lesson_material_path(@course, @lesson)

    assert_select 'select[name="lesson_material[kind]"] option[value="copy"]', text: "Create from copy"
    assert_select "form[action='#{course_lesson_lesson_materials_path(@course, @lesson)}']"
    assert_select "#copy-material-dialog[role='dialog'][aria-hidden='true']" do
      assert_select "select[name='source_course_id'] option[value='#{@course.id}']", text: @course.title
      assert_select ".hidden[data-material-copy-selector-target='lessonGroup'] select[name='source_lesson_id'][disabled]"
      assert_select ".hidden[data-material-copy-selector-target='materialGroup'] select[name='source_material_id'][disabled]"
      assert_select "[data-material-copy-selector-catalog-value*='Pre-read']"
    end
  end

  test "instructor creates an html material" do
    sign_in users(:instructor)
    assert_difference("LessonMaterial.count", 1) do
      post course_lesson_lesson_materials_path(@course, @lesson),
           params: { lesson_material: { title: "New material", kind: "html",
                                        body: "<p>hi</p>", required: "1" } }
    end
    assert_redirected_to edit_course_lesson_path(@course, @lesson)
  end

  test "instructor can start a new material directly with the AI designer" do
    sign_in users(:instructor)

    assert_difference("LessonMaterial.count", 1) do
      post course_lesson_lesson_materials_path(@course, @lesson),
           params: {
             lesson_material: { title: "", kind: "ai_designed" }
           }
    end

    material = LessonMaterial.order(:created_at).last
    assert_equal "Untitled material", material.title
    assert material.raw_html_iframe?
    assert material.blank_ai_design_source?
    assert_redirected_to new_course_lesson_lesson_material_material_design_revision_path(
      @course, @lesson, material
    )
  end

  test "instructor can copy an owned material and open it in the AI designer" do
    sign_in users(:instructor)

    assert_difference("LessonMaterial.count", 1) do
      post copy_course_lesson_lesson_materials_path(@course, @lesson), params: {
        source_material_id: @material.id,
        copy_settings: "1",
        open_in_designer: "1"
      }
    end

    copy = LessonMaterial.order(:created_at).last
    assert_equal @material, copy.source_material
    assert_equal users(:instructor), copy.copied_by
    assert_redirected_to new_course_lesson_lesson_material_material_design_revision_path(
      @course, @lesson, copy
    )
  end

  test "instructor can create from copy through the new material form" do
    sign_in users(:instructor)

    assert_difference("LessonMaterial.count", 1) do
      post course_lesson_lesson_materials_path(@course, @lesson), params: {
        lesson_material: { title: "", kind: "copy" },
        source_material_id: @material.id,
        copy_settings: "1",
        open_in_designer: "1"
      }
    end

    copy = LessonMaterial.order(:created_at).last
    assert_equal @material, copy.source_material
    assert_redirected_to new_course_lesson_lesson_material_material_design_revision_path(
      @course, @lesson, copy
    )
  end

  test "instructor cannot copy another instructor's material" do
    source = LessonMaterial.create!(
      lesson: lessons(:physics_lesson), title: "Private source", kind: :html, body: "No"
    )
    sign_in users(:instructor)

    assert_no_difference("LessonMaterial.count") do
      post copy_course_lesson_lesson_materials_path(@course, @lesson), params: {
        source_material_id: source.id
      }
    end

    assert_redirected_to root_path
  end

  test "instructor sees an import error for an invalid Google Docs ZIP" do
    sign_in users(:instructor)
    invalid_zip = Rack::Test::UploadedFile.new(
      Rails.root.join("test/fixtures/files/poster.png"),
      "application/zip",
      false,
      original_filename: "lesson.zip"
    )

    assert_no_difference("LessonMaterial.count") do
      post course_lesson_lesson_materials_path(@course, @lesson),
           params: { lesson_material: { title: "Imported", kind: "google_doc", google_doc_zip: invalid_zip } }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "not a valid Google Docs ZIP"
  end

  test "Google document HTML cannot be supplied without the importer" do
    sign_in users(:instructor)

    assert_no_difference("LessonMaterial.count") do
      post course_lesson_lesson_materials_path(@course, @lesson),
           params: {
             lesson_material: {
               title: "Injected",
               kind: "google_doc",
               raw_html_content: "<script>alert('no')</script>"
             }
           }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "must be imported from a Google Docs Web Page ZIP"
  end

  test "instructor creates an image upload material" do
    sign_in users(:instructor)
    image = Rack::Test::UploadedFile.new(Rails.root.join("test/fixtures/files/poster.png"), "image/png")

    assert_difference("LessonMaterial.count", 1) do
      post course_lesson_lesson_materials_path(@course, @lesson),
           params: { lesson_material: { title: "Diagram", kind: "image_upload", image_file: image } }
    end

    assert_redirected_to edit_course_lesson_path(@course, @lesson)
    assert LessonMaterial.order(:created_at).last.image_file.attached?
  end

  test "instructor creates a video url material" do
    sign_in users(:instructor)

    assert_difference("LessonMaterial.count", 1) do
      post course_lesson_lesson_materials_path(@course, @lesson),
           params: { lesson_material: { title: "Clip", kind: "video_url", url: "https://example.com/clip.mp4" } }
    end

    material = LessonMaterial.order(:created_at).last
    assert_redirected_to edit_course_lesson_path(@course, @lesson)
    assert_equal "video_url", material.kind
    assert_equal "https://example.com/clip.mp4", material.url
  end

  test "instructor can get edit form for own material" do
    sign_in users(:instructor)
    get edit_course_lesson_lesson_material_path(@course, @lesson, @material)
    assert_response :success
    assert_select "a[href='#{course_lesson_lesson_material_path(@course, @lesson, @material)}'][target='_blank']", text: "View material"
    assert_select "a.ai-design-action[href='#{course_lesson_lesson_material_material_design_revisions_path(@course, @lesson, @material)}']", text: "Design"
  end

  test "instructor can update own material" do
    sign_in users(:instructor)
    patch course_lesson_lesson_material_path(@course, @lesson, @material),
          params: { lesson_material: { title: "Updated Title" } }
    assert_redirected_to edit_course_lesson_path(@course, @lesson)
    assert_equal "Updated Title", @material.reload.title
  end

  test "instructor can configure a material to open by default" do
    sign_in users(:instructor)
    patch course_lesson_lesson_material_path(@course, @lesson, @material),
          params: { lesson_material: { open_by_default: "1" } }

    assert_redirected_to edit_course_lesson_path(@course, @lesson)
    assert @material.reload.open_by_default?
  end

  test "lesson material uses its configured default display state" do
    get course_lesson_path(@course, @lesson)
    assert_select "#material-#{@material.id}[data-expanded='false']"

    @material.update!(open_by_default: true)
    get course_lesson_path(@course, @lesson)
    assert_select "#material-#{@material.id}[data-expanded='true']"
  end

  test "instructor can destroy own material" do
    sign_in users(:instructor)
    assert_difference("LessonMaterial.count", -1) do
      delete course_lesson_lesson_material_path(@course, @lesson, @material)
    end
    assert_redirected_to edit_course_lesson_path(@course, @lesson, open_materials: 1)
    follow_redirect!
    assert_select "#lesson-materials-editor[data-expanded='true']"
  end

  test "instructor can reorder materials" do
    m2 = LessonMaterial.create!(lesson: @lesson, title: "Second", kind: :html, body: "x")
    sign_in users(:instructor)
    post reorder_course_lesson_lesson_materials_path(@course, @lesson),
         params: { ids: [ m2.id, @material.id ] }
    assert_response :no_content
    assert_equal 1, m2.reload.position
    assert_equal 2, @material.reload.position
  end

  # ---------------------------------------------------------------------------
  # Non-owner instructor — all mutations denied
  # ---------------------------------------------------------------------------

  test "non-owner instructor cannot create material" do
    sign_in users(:other_instructor)
    post course_lesson_lesson_materials_path(@course, @lesson),
         params: { lesson_material: { title: "X", kind: "html", body: "x" } }
    assert_redirected_to root_path
  end

  test "non-owner instructor cannot get edit form" do
    sign_in users(:other_instructor)
    get edit_course_lesson_lesson_material_path(@course, @lesson, @material)
    assert_redirected_to root_path
  end

  test "non-owner instructor cannot update material" do
    sign_in users(:other_instructor)
    patch course_lesson_lesson_material_path(@course, @lesson, @material),
          params: { lesson_material: { title: "Hacked" } }
    assert_redirected_to root_path
  end

  test "non-owner instructor cannot destroy material" do
    sign_in users(:other_instructor)
    delete course_lesson_lesson_material_path(@course, @lesson, @material)
    assert_redirected_to root_path
  end

  test "non-owner instructor cannot reorder materials" do
    sign_in users(:other_instructor)
    post reorder_course_lesson_lesson_materials_path(@course, @lesson),
         params: { ids: [ @material.id ] }
    assert_redirected_to root_path
  end

  # ---------------------------------------------------------------------------
  # Admin — unrestricted
  # ---------------------------------------------------------------------------

  test "admin can create a material" do
    sign_in users(:admin)
    assert_difference("LessonMaterial.count", 1) do
      post course_lesson_lesson_materials_path(@course, @lesson),
           params: { lesson_material: { title: "Admin material", kind: "html", body: "x" } }
    end
    assert_redirected_to edit_course_lesson_path(@course, @lesson)
  end

  test "admin can destroy any material" do
    sign_in users(:admin)
    assert_difference("LessonMaterial.count", -1) do
      delete course_lesson_lesson_material_path(@course, @lesson, @material)
    end
    assert_redirected_to edit_course_lesson_path(@course, @lesson, open_materials: 1)
  end

  # ---------------------------------------------------------------------------
  # Acknowledge — edge cases
  # ---------------------------------------------------------------------------

  test "enrolled student acknowledges a material" do
    sign_in users(:student)
    assert_difference("LessonMaterialAcknowledgement.count", 1) do
      post acknowledge_course_lesson_lesson_material_path(@course, @lesson, @material)
    end
    assert_redirected_to course_lesson_path(@course, @lesson,
                                            anchor: "material-#{@material.id}")
  end

  test "double-acknowledge is idempotent" do
    enrollment = enrollments(:student_in_algebra)
    LessonMaterialAcknowledgement.create!(lesson_material: @material, enrollment: enrollment)
    sign_in users(:student)
    assert_no_difference("LessonMaterialAcknowledgement.count") do
      post acknowledge_course_lesson_lesson_material_path(@course, @lesson, @material)
    end
    assert_redirected_to course_lesson_path(@course, @lesson,
                                            anchor: "material-#{@material.id}")
  end

  # ---------------------------------------------------------------------------
  # Quiz gate
  # ---------------------------------------------------------------------------

  test "submit_quiz is blocked until required material is acknowledged" do
    sign_in users(:student)
    post submit_quiz_course_lesson_path(@course, @lesson),
         params: { answers: { questions(:intro_q1).id.to_s => "2" } }
    assert_redirected_to course_lesson_path(@course, @lesson)
    follow_redirect!
    assert_match "Complete the required materials", flash[:alert].to_s + @response.body
  end
end
