require "test_helper"

class MaterialDesignAssetTest < ActiveSupport::TestCase
  test "accepts a video as a content asset" do
    asset = build_asset(
      role: :content,
      file: Rack::Test::UploadedFile.new(
        Rails.root.join("test/fixtures/files/clip.mp4"), "video/mp4", true
      )
    )

    assert asset.valid?
    assert asset.video?
    assert_not asset.image?
  end

  test "does not accept a video as a design reference" do
    asset = build_asset(
      role: :design_reference,
      file: Rack::Test::UploadedFile.new(
        Rails.root.join("test/fixtures/files/clip.mp4"), "video/mp4", true
      )
    )

    assert_not asset.valid?
    assert_includes asset.errors[:role], "must be page content for a video"
  end

  private

  def build_asset(attributes)
    MaterialDesignAsset.new(
      {
        lesson_material: LessonMaterial.create!(
          lesson: lessons(:intro), title: "Designed material", kind: :raw_html_iframe,
          raw_html_content: LessonMaterial::AI_DESIGN_STARTER_HTML
        ),
        created_by: users(:instructor),
        name: "Lesson clip"
      }.merge(attributes)
    )
  end
end
