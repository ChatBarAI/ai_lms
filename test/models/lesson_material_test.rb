require "test_helper"

class LessonMaterialTest < ActiveSupport::TestCase
  setup do
    @lesson = lessons(:intro)
  end

  test "html material requires body" do
    r = LessonMaterial.new(lesson: @lesson, title: "T", kind: :html)
    assert_not r.valid?
    assert_includes r.errors[:body], "can't be blank"
  end

  test "pdf material requires document" do
    r = LessonMaterial.new(lesson: @lesson, title: "T", kind: :pdf)
    assert_not r.valid?
    assert_includes r.errors[:document], "must be attached for a PDF material"
  end

  test "html material saves with body" do
    r = LessonMaterial.new(lesson: @lesson, title: "T", kind: :html)
    r.body = "<p>Hello</p>"
    assert r.save, r.errors.full_messages.to_sentence
  end

  test "assigns next position on create" do
    LessonMaterial.create!(lesson: @lesson, title: "A", kind: :html, body: "x")
    r2 = LessonMaterial.create!(lesson: @lesson, title: "B", kind: :html, body: "y")
    assert r2.position >= 1
  end

  test "audio_url material requires url" do
    r = LessonMaterial.new(lesson: @lesson, title: "T", kind: :audio_url)
    assert_not r.valid?
    assert_includes r.errors[:url], "can't be blank"
  end

  test "image_upload material requires image file" do
    r = LessonMaterial.new(lesson: @lesson, title: "Image", kind: :image_upload)
    assert_not r.valid?
    assert_includes r.errors[:image_file], "must be attached for an uploaded image material"
  end

  test "video_upload material requires video file" do
    r = LessonMaterial.new(lesson: @lesson, title: "Video", kind: :video_upload)
    assert_not r.valid?
    assert_includes r.errors[:video_file], "must be attached for an uploaded video material"
  end

  test "video_url material requires url" do
    r = LessonMaterial.new(lesson: @lesson, title: "Video", kind: :video_url)
    assert_not r.valid?
    assert_includes r.errors[:url], "can't be blank"
  end

  test "google doc material requires imported content" do
    material = LessonMaterial.new(lesson: @lesson, title: "Imported", kind: :google_doc)

    assert_not material.valid?
    assert_includes material.errors[:google_doc_zip], "must be imported from a Google Docs Web Page ZIP"
  end

  test "raw html preserves safe layout styles and table structure" do
    material = LessonMaterial.create!(
      lesson: @lesson,
      title: "Styled HTML",
      kind: :raw_html,
      raw_html_content: <<~HTML
        <p style="margin-left: 36pt; color: #123456; font-family: Roboto; position: fixed; background-image: url(https://tracker.example/pixel)">Styled</p>
        <table><colgroup><col style="width: 120pt"></colgroup><tbody><tr><td colspan="2">Cell</td></tr></tbody></table>
      HTML
    )

    assert_includes material.raw_html_content, "margin-left:36pt"
    assert_includes material.raw_html_content, "color:#123456"
    assert_includes material.raw_html_content, "font-family:&quot;Roboto&quot;, system-ui"
    assert_includes material.raw_html_content, "<colgroup>"
    assert_includes material.raw_html_content, "width:120pt"
    assert_includes material.raw_html_content, 'colspan="2"'
    assert_not_includes material.raw_html_content, "position:fixed"
    assert_not_includes material.raw_html_content, "tracker.example"
  end

  test "raw html still removes executable content" do
    material = LessonMaterial.create!(
      lesson: @lesson,
      title: "Unsafe HTML",
      kind: :raw_html,
      raw_html_content: '<script>alert("no")</script><form action="/users"><input name="admin"></form><p onclick="alert(1)">Safe text</p>'
    )

    assert_not_includes material.raw_html_content, "<script"
    assert_not_includes material.raw_html_content, "<form"
    assert_not_includes material.raw_html_content, "<input"
    assert_not_includes material.raw_html_content, "onclick"
    assert_not_includes material.raw_html_content, 'alert("no")'
    assert_includes material.raw_html_content, "Safe text"
  end

  test "isolated raw html preserves sanitized stylesheet blocks" do
    material = LessonMaterial.create!(
      lesson: @lesson,
      title: "Isolated HTML",
      kind: :raw_html_iframe,
      raw_html_content: <<~HTML
        <!doctype html>
        <html>
          <head>
            <style>
              @import url(https://tracker.example/font.css);
              .card { color: #123456; font-family: Roboto; background-image: url(https://tracker.example/pixel); }
            </style>
          </head>
          <body class="document"><div class="card">Styled card</div><script>alert("no")</script></body>
        </html>
      HTML
    )

    assert_includes material.raw_html_content, "<!doctype html>"
    assert_includes material.raw_html_content, ".card { color: #123456"
    assert_includes material.raw_html_content, 'font-family:"Roboto", system-ui'
    assert_includes material.raw_html_content, 'class="document"'
    assert_not_includes material.raw_html_content, "tracker.example"
    assert_not_includes material.raw_html_content, "<script"
  end

  test "isolated raw html requires content" do
    material = LessonMaterial.new(lesson: @lesson, title: "Empty", kind: :raw_html_iframe, raw_html_content: "")

    assert_not material.valid?
    assert_includes material.errors[:raw_html_content], "can't be blank"
  end

  test "web page material requires a URL and imported snapshot" do
    material = LessonMaterial.new(lesson: @lesson, title: "Web page", kind: :web_page)

    assert_not material.valid?
    assert_includes material.errors[:url], "can't be blank"
    assert_includes material.errors[:raw_html_content], "must be imported from a public web page URL"
  end
end

class LessonMaterialsGatingTest < ActiveSupport::TestCase
  setup do
    @lesson = lessons(:intro)
    @enrollment = enrollments(:student_in_algebra)
  end

  test "complete? returns true when no required materials" do
    assert @lesson.lesson_materials_complete_for?(@enrollment)
  end

  test "complete? false until all required materials acknowledged" do
    m1 = LessonMaterial.create!(lesson: @lesson, title: "M1", kind: :html, body: "a", required: true)
    m2 = LessonMaterial.create!(lesson: @lesson, title: "M2", kind: :html, body: "b", required: false)

    assert_not @lesson.lesson_materials_complete_for?(@enrollment)

    LessonMaterialAcknowledgement.create!(lesson_material: m1, enrollment: @enrollment)
    @lesson.reload
    assert @lesson.lesson_materials_complete_for?(@enrollment)
    assert m2.acknowledged_by?(@enrollment) == false
  end
end
