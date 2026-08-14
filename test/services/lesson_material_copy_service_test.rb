require "test_helper"

class LessonMaterialCopyServiceTest < ActiveSupport::TestCase
  test "copies material files and imported assets into new blobs" do
    source = LessonMaterial.create!(
      lesson: lessons(:intro), title: "Illustrated handout", kind: :image_upload,
      required: false, open_by_default: true,
      image_file: Rack::Test::UploadedFile.new(
        Rails.root.join("test/fixtures/files/poster.png"), "image/png"
      )
    )
    source.imported_assets.attach(
      io: StringIO.new("imported image"), filename: "imported.png", content_type: "image/png"
    )

    copy = copy_material(source)

    assert_equal source, copy.source_material
    assert_equal users(:instructor), copy.copied_by
    assert_equal source.required, copy.required
    assert_equal source.open_by_default, copy.open_by_default
    assert copy.image_file.attached?
    assert_not_equal source.image_file.blob_id, copy.image_file.blob_id
    assert_equal source.image_file.download, copy.image_file.download
    assert_not_equal source.imported_assets.first.blob_id, copy.imported_assets.first.blob_id
  end

  test "copies design assets and rewrites source-owned URLs" do
    source = LessonMaterial.create!(
      lesson: lessons(:intro), title: "Designed page", kind: :raw_html_iframe,
      raw_html_content: LessonMaterial::AI_DESIGN_STARTER_HTML
    )
    asset = source.material_design_assets.create!(
      created_by: users(:instructor), name: "Diagram", role: :content,
      file: Rack::Test::UploadedFile.new(
        Rails.root.join("test/fixtures/files/poster.png"), "image/png"
      )
    )
    old_path = Rails.application.routes.url_helpers.material_design_asset_file_path(
      asset.signed_id(purpose: :material_design_asset)
    )
    source.update!(raw_html_content: "<html><body><img src=\"#{old_path}\"></body></html>")

    copy = copy_material(source)
    copied_asset = copy.material_design_assets.first
    new_path = Rails.application.routes.url_helpers.material_design_asset_file_path(
      copied_asset.signed_id(purpose: :material_design_asset)
    )

    assert_not_equal asset.file.blob_id, copied_asset.file.blob_id
    assert_includes copy.raw_html_content, new_path
    assert_not_includes copy.raw_html_content, old_path
    assert_empty copy.material_design_revisions
  end

  test "does not copy learner acknowledgements or design revisions" do
    source = LessonMaterial.create!(lesson: lessons(:intro), title: "Text", kind: :html, body: "Read me")
    LessonMaterialAcknowledgement.create!(
      lesson_material: source, enrollment: enrollments(:student_in_algebra)
    )

    copy = copy_material(source)

    assert_empty copy.acknowledgements
    assert_empty copy.material_design_revisions
  end

  private

  def copy_material(source)
    LessonMaterialCopyService.new(
      source: source,
      destination_lesson: lessons(:physics_lesson),
      copied_by: users(:instructor),
      copy_settings: true
    ).call
  end
end
