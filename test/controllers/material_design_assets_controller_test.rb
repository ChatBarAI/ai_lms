require "test_helper"

class MaterialDesignAssetsControllerTest < ActionDispatch::IntegrationTest
  test "uploads a video as a content asset" do
    sign_in users(:instructor)
    material = LessonMaterial.create!(
      lesson: lessons(:intro), title: "Video content", kind: :raw_html_iframe,
      raw_html_content: LessonMaterial::AI_DESIGN_STARTER_HTML
    )

    assert_difference("MaterialDesignAsset.count", 1) do
      post course_lesson_lesson_material_material_design_assets_path(
        material.lesson.course, material.lesson, material
      ), params: {
        material_design_asset: {
          name: "Worked example", description: "A narrated example", role: "content",
          file: Rack::Test::UploadedFile.new(
            Rails.root.join("test/fixtures/files/clip.mp4"), "video/mp4", true
          )
        }
      }
    end

    asset = MaterialDesignAsset.order(:id).last
    assert asset.video?
    assert asset.content?
    assert_redirected_to course_lesson_lesson_material_material_design_revisions_path(
      material.lesson.course, material.lesson, material
    )
  end

  test "uploads an image with an explicit design-reference role" do
    sign_in users(:instructor)
    material = LessonMaterial.create!(
      lesson: lessons(:intro), title: "Design reference", kind: :raw_html_iframe,
      raw_html_content: "<html><body><p>Document</p></body></html>"
    )

    assert_difference("MaterialDesignAsset.count", 1) do
      post course_lesson_lesson_material_material_design_assets_path(
        material.lesson.course, material.lesson, material
      ), params: {
        material_design_asset: {
          name: "Draft screenshot", role: "design_reference",
          file: Rack::Test::UploadedFile.new(
            Rails.root.join("test/fixtures/files/poster.png"), "image/png", true
          )
        }
      }
    end

    assert MaterialDesignAsset.order(:id).last.design_reference?
  end

  test "serves an uploaded design asset to the lesson owner" do
    sign_in users(:instructor)
    material = LessonMaterial.create!(
      lesson: lessons(:intro), title: "Design source", kind: :raw_html_iframe,
      raw_html_content: "<html><body><p>Document</p></body></html>"
    )
    asset = MaterialDesignAsset.create!(
      lesson_material: material, created_by: users(:instructor), name: "Thumbnail",
      file: Rack::Test::UploadedFile.new(
        Rails.root.join("test/fixtures/files/poster.png"), "image/png", true
      )
    )

    get material_design_asset_file_path(
      asset.signed_id(purpose: :material_design_asset)
    )

    assert_response :redirect
    assert_equal "private, no-store", response.headers["Cache-Control"]
    follow_redirect!
    assert_response :success
  end

  test "reclassifies an existing image without re-uploading it" do
    sign_in users(:instructor)
    material = LessonMaterial.create!(
      lesson: lessons(:intro), title: "Reclassified image", kind: :raw_html_iframe,
      raw_html_content: "<html><body><p>Document</p></body></html>"
    )
    asset = MaterialDesignAsset.create!(
      lesson_material: material, created_by: users(:instructor), name: "Draft", role: :content,
      file: Rack::Test::UploadedFile.new(
        Rails.root.join("test/fixtures/files/poster.png"), "image/png", true
      )
    )

    patch course_lesson_lesson_material_material_design_asset_path(
      material.lesson.course, material.lesson, material, asset
    ), params: { material_design_asset: { role: "design_reference", name: "Ignored" } }

    assert_redirected_to course_lesson_lesson_material_material_design_revisions_path(
      material.lesson.course, material.lesson, material
    )
    assert asset.reload.design_reference?
    assert_equal "Draft", asset.name
  end

  test "serves an imported material asset using its Active Storage signed id" do
    sign_in users(:instructor)
    material = LessonMaterial.create!(
      lesson: lessons(:intro), title: "Imported thumbnail", kind: :raw_html_iframe,
      raw_html_content: "<html><body><p>Document</p></body></html>"
    )
    material.imported_assets.attach(
      io: Rails.root.join("test/fixtures/files/poster.png").open,
      filename: "poster.png",
      content_type: "image/png"
    )
    attachment = material.imported_assets.attachments.first

    get material_design_imported_asset_file_path(
      ActiveStorage.verifier.generate(
        attachment.id, purpose: :material_design_imported_asset
      )
    )

    assert_response :redirect
    assert_includes response.location, "/rails/active_storage/"
  end

  test "returns not found for an invalid imported asset token" do
    sign_in users(:instructor)

    get material_design_imported_asset_file_path("invalid")

    assert_response :not_found
  end

  test "removes an uploaded image and returns to the generate design page" do
    sign_in users(:instructor)
    material = LessonMaterial.create!(
      lesson: lessons(:intro), title: "Removable image", kind: :raw_html_iframe,
      raw_html_content: "<html><body><p>Document</p></body></html>"
    )
    asset = MaterialDesignAsset.create!(
      lesson_material: material, created_by: users(:instructor), name: "Draft",
      file: Rack::Test::UploadedFile.new(
        Rails.root.join("test/fixtures/files/poster.png"), "image/png", true
      )
    )

    assert_difference("MaterialDesignAsset.count", -1) do
      delete course_lesson_lesson_material_material_design_asset_path(
        material.lesson.course, material.lesson, material, asset
      ), params: { return_to: "new_design" }
    end

    assert_redirected_to new_course_lesson_lesson_material_material_design_revision_path(
      material.lesson.course, material.lesson, material
    )
  end

  test "removes an imported image owned by the material" do
    sign_in users(:instructor)
    material = LessonMaterial.create!(
      lesson: lessons(:intro), title: "Imported image", kind: :raw_html_iframe,
      raw_html_content: "<html><body><p>Document</p></body></html>"
    )
    material.imported_assets.attach(
      io: Rails.root.join("test/fixtures/files/poster.png").open,
      filename: "poster.png", content_type: "image/png"
    )
    attachment = material.imported_assets.attachments.first
    token = ActiveStorage.verifier.generate(
      attachment.id, purpose: :material_design_imported_asset
    )

    assert_difference("material.imported_assets.attachments.count", -1) do
      delete imported_course_lesson_lesson_material_material_design_assets_path(
        material.lesson.course, material.lesson, material, id: token
      ), params: { return_to: "new_design" }
    end

    assert_redirected_to new_course_lesson_lesson_material_material_design_revision_path(
      material.lesson.course, material.lesson, material
    )
  end
end
