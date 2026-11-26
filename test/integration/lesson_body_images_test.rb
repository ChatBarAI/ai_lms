require "test_helper"
require "image_processing/vips"

class LessonBodyImagesTest < ActionDispatch::IntegrationTest
  test "images in lesson text are served as resized WebP variants" do
    lesson = lessons(:intro)
    png = (Vips::Image.black(2048, 1024, bands: 3) + [ 200, 80, 40 ]).cast(:uchar).copy(interpretation: :srgb).pngsave_buffer
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(png), filename: "body.png", content_type: "image/png")
    lesson.update!(body: %(<p>Diagram:</p><action-text-attachment sgid="#{blob.attachable_sgid}"></action-text-attachment>))
    sign_in users(:admin)

    get course_lesson_path(lesson.course, lesson)

    assert_response :success
    src = css_select(".trix-content figure.attachment img").first&.[]("src")
    assert_includes src.to_s, "/rails/active_storage/representations/proxy/"

    variation = ActiveStorage::Variation.decode(src.split("/")[-2])
    assert_equal :webp, variation.transformations[:format].to_sym
    assert_equal [ 1024, 768 ], variation.transformations[:resize_to_limit]
  end
end
