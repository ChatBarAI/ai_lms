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

  test "instructor creates an html material" do
    sign_in users(:instructor)
    assert_difference("LessonMaterial.count", 1) do
      post course_lesson_lesson_materials_path(@course, @lesson),
           params: { lesson_material: { title: "New material", kind: "html",
                                        body: "<p>hi</p>", required: "1" } }
    end
    assert_redirected_to edit_course_lesson_path(@course, @lesson)
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

  test "instructor can get edit form for own material" do
    sign_in users(:instructor)
    get edit_course_lesson_lesson_material_path(@course, @lesson, @material)
    assert_response :success
  end

  test "instructor can update own material" do
    sign_in users(:instructor)
    patch course_lesson_lesson_material_path(@course, @lesson, @material),
          params: { lesson_material: { title: "Updated Title" } }
    assert_redirected_to edit_course_lesson_path(@course, @lesson)
    assert_equal "Updated Title", @material.reload.title
  end

  test "instructor can destroy own material" do
    sign_in users(:instructor)
    assert_difference("LessonMaterial.count", -1) do
      delete course_lesson_lesson_material_path(@course, @lesson, @material)
    end
    assert_redirected_to edit_course_lesson_path(@course, @lesson)
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
    assert_redirected_to edit_course_lesson_path(@course, @lesson)
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
