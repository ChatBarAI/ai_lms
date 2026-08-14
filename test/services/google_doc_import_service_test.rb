require "test_helper"
require "zip"

class GoogleDocImportServiceTest < ActiveSupport::TestCase
  setup do
    @archive = Tempfile.new([ "google-doc", ".zip" ])
    @archive.binmode

    Zip::File.open(@archive.path, create: true) do |zip|
      zip.get_output_stream("Lesson.html") do |file|
        file.write <<~HTML
          <!doctype html>
          <html>
            <head>
              <title>Brochure title</title>
              <style>
                @import url(https://tracker.example/styles.css);
                .title { color: red; font-family: 'Roboto'; background-image: url(https://tracker.example/pixel); }
              </style>
            </head>
            <body class="doc-content page" style="max-width: 468pt; padding: 72pt; position: fixed" dir="ltr" lang="en-GB">
              <h1 class="title">Imported lesson</h1>
              <p style="margin-left: 36pt; color: #123456; font-family: Merriweather; position: fixed; background-image: url(https://tracker.example/inline)">Styled paragraph</p>
              <table><colgroup><col style="width: 120pt"></colgroup><tbody><tr><td>Cell</td></tr></tbody></table>
              <script>alert('no')</script>
              <form action="https://example.com"><input name="secret"></form>
              <a href="https://example.com/help">Help</a>
              <img src="Lesson_files/picture.png">
              <img src="Lesson_files/picture.png">
            </body>
          </html>
        HTML
      end
      zip.add("Lesson_files/picture.png", Rails.root.join("test/fixtures/files/poster.png"))
    end

    @upload = Rack::Test::UploadedFile.new(@archive.path, "application/zip", true)
  end

  teardown do
    @upload&.close
    @archive&.close!
  end

  test "imports sanitized HTML and local images as an isolated document" do
    material = LessonMaterial.new(
      lesson: lessons(:intro),
      title: "",
      kind: :google_doc
    )

    GoogleDocImportService.new(material: material, upload: @upload).call

    assert material.persisted?
    assert_equal "Brochure title", material.title
    assert_equal 1, material.imported_assets.count
    assert_includes material.raw_html_content, "Imported lesson"
    assert_includes material.raw_html_content, "rails/active_storage"
    assert_includes material.raw_html_content, 'target="_blank"'
    assert_includes material.raw_html_content, "margin-left:36pt"
    assert_includes material.raw_html_content, "color:#123456"
    assert_includes material.raw_html_content, 'font-family:"Roboto", system-ui'
    assert_includes material.raw_html_content, "font-family:&quot;Merriweather&quot;, Georgia"
    assert_includes material.raw_html_content, "<colgroup>"
    assert_includes material.raw_html_content, "width:120pt"
    assert_includes material.raw_html_content, 'class="doc-content page"'
    assert_includes material.raw_html_content, 'style="max-width:468pt;padding:72pt;"'
    assert_includes material.raw_html_content, 'dir="ltr"'
    assert_includes material.raw_html_content, 'lang="en-GB"'
    assert_not_includes material.raw_html_content, "<script"
    assert_not_includes material.raw_html_content, "alert('no')"
    assert_not_includes material.raw_html_content, "<form"
    assert_not_includes material.raw_html_content, "@import"
    assert_not_includes material.raw_html_content, "tracker.example"
    assert_not_includes material.raw_html_content, "position:fixed"
  end

  test "purges newly created blobs when the material cannot be saved" do
    material = LessonMaterial.new(
      lesson: lessons(:intro),
      title: "Invalid import",
      kind: :google_doc,
      position: -1
    )

    assert_no_difference("ActiveStorage::Blob.count") do
      assert_raises(ActiveRecord::RecordInvalid) do
        GoogleDocImportService.new(material: material, upload: @upload).call
      end
    end
  end
end
