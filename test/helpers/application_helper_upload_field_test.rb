require "test_helper"

class ApplicationHelperUploadFieldTest < ActionView::TestCase
  tests ApplicationHelper
  include Rails.application.routes.url_helpers

  setup do
    @course = courses(:algebra)
  end

  test "image upload_field includes cropper controls" do
    html = form_with(model: @course, url: "/courses") do |f|
      upload_field f, :cover_image,
                   label: "Upload cover",
                   accept: "image/png,image/jpeg,image/webp",
                   crop_size: [ 728, 320 ]
    end

    assert_includes html, 'data-controller="file-preview image-crop"'
    assert_includes html, 'data-image-crop-width-value="728"'
    assert_includes html, 'data-image-crop-height-value="320"'
    assert_includes html, 'data-image-crop-target="adjustButton"'
    assert_includes html, "Adjust image"
    assert_includes html, "Replace image"
    assert_includes html, "or drag and drop to replace"
    assert_match(/<dialog[^>]*data-image-crop-target="dialog"/, html)
    assert_includes html, 'change-&gt;image-crop#fileChanged'
  end

  test "image upload_field with current attachment exposes crop source url" do
    @course.cover_image.attach(
      io: File.open(Rails.root.join("test/fixtures/files/poster.png")),
      filename: "poster.png",
      content_type: "image/png"
    )

    html = form_with(model: @course, url: "/courses") do |f|
      upload_field f, :cover_image,
                   label: "Upload cover",
                   accept: "image/png",
                   current_attachment: @course.cover_image,
                   crop_size: [ 728, 320 ]
    end

    assert_includes html, "data-image-crop-source-url-value="
    assert_includes html, "Adjust image"
    assert_includes html, "Replace image"
  end

  test "image upload_field without crop_size still enables free crop" do
    html = form_with(model: @course, url: "/courses") do |f|
      upload_field f, :cover_image,
                   label: "Upload cover",
                   accept: "image/png"
    end

    assert_includes html, 'data-controller="file-preview image-crop"'
    assert_not_includes html, "data-image-crop-width-value"
    assert_includes html, "Adjust image"
  end

  test "file upload_field does not include cropper" do
    html = form_with(model: @course, url: "/courses") do |f|
      upload_field f, :cover_image,
                   label: "Upload file",
                   accept: "application/pdf",
                   preview_type: :file
    end

    assert_includes html, 'data-controller="file-preview"'
    assert_not_includes html, "image-crop"
    assert_not_includes html, "Adjust image"
  end
end
