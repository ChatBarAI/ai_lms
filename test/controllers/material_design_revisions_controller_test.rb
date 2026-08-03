require "test_helper"

class MaterialDesignRevisionsControllerTest < ActionDispatch::IntegrationTest
  test "creating a revision redirects to the designs page" do
    sign_in users(:instructor)
    material = LessonMaterial.create!(
      lesson: lessons(:intro), title: "Designed material", kind: :raw_html_iframe,
      raw_html_content: "<html><body>Material</body></html>"
    )
    configuration = AiModelConfiguration.create!(
      name: "Test model", provider: "openai", model: "test-model",
      base_url: "https://api.openai.com/v1", api_key: "secret"
    )

    post course_lesson_lesson_material_material_design_revisions_path(
      material.lesson.course, material.lesson, material
    ), params: {
      material_design_revision: {
        request: "Improve the layout",
        ai_model_configuration_id: configuration.id
      }
    }

    assert_redirected_to course_lesson_lesson_material_material_design_revisions_path(
      material.lesson.course, material.lesson, material
    )
    assert_equal "Design revision queued.", flash[:notice]
  end

  test "does not queue a second active generation for the same material" do
    sign_in users(:instructor)
    material = LessonMaterial.create!(
      lesson: lessons(:intro), title: "Designed material", kind: :raw_html_iframe,
      raw_html_content: "<html><body>Material</body></html>"
    )
    configuration = AiModelConfiguration.create!(
      name: "Test model", provider: "openai", model: "test-model",
      base_url: "https://api.openai.com/v1", api_key: "secret"
    )
    material.material_design_revisions.create!(
      ai_model_configuration: configuration, created_by: users(:instructor),
      request: "First design", status: "generating"
    )

    assert_no_difference("MaterialDesignRevision.count") do
      post course_lesson_lesson_material_material_design_revisions_path(
        material.lesson.course, material.lesson, material
      ), params: {
        material_design_revision: {
          request: "Second design", ai_model_configuration_id: configuration.id
        }
      }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "already has a design generation in progress"
  end

  test "new revision identifies an accepted parent as the source" do
    sign_in users(:instructor)
    material = LessonMaterial.create!(
      lesson: lessons(:intro), title: "Designed material", kind: :raw_html_iframe,
      raw_html_content: "<html><body>Accepted material</body></html>"
    )
    configuration = AiModelConfiguration.create!(
      name: "Test model", provider: "openai", model: "test-model",
      base_url: "https://api.openai.com/v1", api_key: "secret"
    )
    revision = material.material_design_revisions.create!(
      ai_model_configuration: configuration, created_by: users(:instructor),
      request: "Improve the layout", status: "accepted", accepted_at: Time.current,
      sanitized_html: "<html><body>Accepted revision</body></html>"
    )

    get new_course_lesson_lesson_material_material_design_revision_path(
      material.lesson.course, material.lesson, material, parent_revision_id: revision.id
    )

    assert_response :success
    assert_select "span", text: "Accepted version", count: 2
    assert_select "button.ai-design-action[type='submit']", text: "Generate revision"
  end

  test "designs page uses the AI icon on the generate revision link" do
    sign_in users(:instructor)
    material = LessonMaterial.create!(
      lesson: lessons(:intro), title: "Designed material", kind: :raw_html_iframe,
      raw_html_content: "<html><body>Material</body></html>"
    )

    get course_lesson_lesson_material_material_design_revisions_path(
      material.lesson.course, material.lesson, material
    )

    assert_response :success
    assert_select "a.ai-design-action[href='#{new_course_lesson_lesson_material_material_design_revision_path(material.lesson.course, material.lesson, material)}']",
                  text: "Generate revision"
    assert_select "[data-controller='material-design-revisions-channel']" \
                  "[data-material-design-revisions-channel-lesson-material-id-value='#{material.id}']"
    assert_select "[data-material-design-revisions-channel-target='announcement'][aria-live='polite']"
  end

  test "image thumbnails open accessible preview dialogs" do
    sign_in users(:instructor)
    material = LessonMaterial.create!(
      lesson: lessons(:intro), title: "Designed material", kind: :raw_html_iframe,
      raw_html_content: "<html><body>Material</body></html>"
    )
    asset = MaterialDesignAsset.create!(
      lesson_material: material, created_by: users(:instructor), name: "Ruby diagram",
      file: Rack::Test::UploadedFile.new(
        Rails.root.join("test/fixtures/files/poster.png"), "image/png", true
      )
    )
    material.imported_assets.attach(
      Rack::Test::UploadedFile.new(
        Rails.root.join("test/fixtures/files/poster.png"), "image/png", true,
        original_filename: "imported-poster.png"
      )
    )

    get new_course_lesson_lesson_material_material_design_revision_path(
      material.lesson.course, material.lesson, material
    )

    assert_response :success
    assert_select "button[aria-controls='design-asset-image-preview-#{asset.id}-dialog'][aria-haspopup='dialog']",
                  count: 1
    assert_select "img[src*='v=#{asset.file.blob_id}']", minimum: 1
    assert_select "#design-asset-image-preview-#{asset.id}-dialog[role='dialog'][aria-hidden='true'] img",
                  count: 1
    assert_select "button[aria-controls='imported-image-preview-0-dialog'][aria-haspopup='dialog']", count: 1
    assert_select "#imported-image-preview-0-dialog[role='dialog'][aria-hidden='true'] img", count: 1
    assert_select "button.design-assets-panel-toggle[aria-label='Hide images'][aria-expanded='true']" do
      assert_select ".design-assets-panel-toggle-icon[aria-hidden='true']", count: 1
      assert_select ".design-assets-panel-count", text: "2"
    end
    assert_select ".design-request-grid .design-model-field", count: 1
    assert_select "[data-controller='file-preview']" do
      assert_select "input[type='file'][data-action='change->file-preview#update']", count: 1
      assert_select "[data-file-preview-target='previewContainer'].hidden img[data-file-preview-target='preview']", count: 1
      assert_select "[data-file-preview-target='filename']", count: 1
    end
    assert_includes response.body, "dark:bg-indigo-950/50"
    assert_includes response.body, "dark:bg-gray-800"
  end

  test "blank AI starter material is presented as having no source document" do
    sign_in users(:instructor)
    material = LessonMaterial.create!(
      lesson: lessons(:intro), title: "New AI material", kind: :raw_html_iframe,
      raw_html_content: LessonMaterial::AI_DESIGN_STARTER_HTML
    )

    get source_preview_course_lesson_lesson_material_material_design_revisions_path(
      material.lesson.course, material.lesson, material
    )

    assert_response :success
    assert_includes response.body, "No source document. This revision will start from zero."
  end

  test "owner deletes a revision without changing the material" do
    sign_in users(:instructor)
    material = LessonMaterial.create!(
      lesson: lessons(:intro), title: "Designed material", kind: :raw_html_iframe,
      raw_html_content: "<html><body>Applied material</body></html>"
    )
    configuration = AiModelConfiguration.create!(
      name: "Test model", provider: "openai", model: "test-model",
      base_url: "https://api.openai.com/v1", api_key: "secret"
    )
    revision = material.material_design_revisions.create!(
      ai_model_configuration: configuration, created_by: users(:instructor),
      request: "Improve the layout", status: "ready",
      sanitized_html: "<html><body>Revision</body></html>"
    )

    assert_difference("MaterialDesignRevision.count", -1) do
      delete course_lesson_lesson_material_material_design_revision_path(
        material.lesson.course, material.lesson, material, revision
      )
    end

    assert_redirected_to course_lesson_lesson_material_material_design_revisions_path(
      material.lesson.course, material.lesson, material
    )
    assert_includes material.reload.raw_html_content, "Applied material"
  end
end
