require "test_helper"

class MaterialDesignAssetCatalogTest < ActiveSupport::TestCase
  test "automatically exposes imported material images" do
    material = LessonMaterial.create!(
      lesson: lessons(:intro), title: "Imported images", kind: :raw_html_iframe,
      raw_html_content: '<html><body><img src="/rails/active_storage/blobs/proxy/token/poster.png" alt="Course poster"></body></html>'
    )
    material.imported_assets.attach(
      io: Rails.root.join("test/fixtures/files/poster.png").open,
      filename: "poster.png",
      content_type: "image/png"
    )

    entries = MaterialDesignAssetCatalog.new(material).entries

    assert_equal 1, entries.size
    assert_equal :imported, entries.first.source
    assert_equal "poster.png", entries.first.name
    assert_equal "Course poster", entries.first.alt_text
    assert entries.first.referenced_in_source
    assert_match %r{\Aasset://imported/}, entries.first.token
    assert_includes entries.first.url, "/material-design-imported-assets/"
    assert_includes MaterialDesignAssetCatalog.new(material).tokenize_html(material.raw_html_content),
                    entries.first.token
  end
end
