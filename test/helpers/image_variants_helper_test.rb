require "test_helper"
require "image_processing/vips"

class ImageVariantsHelperTest < ActionView::TestCase
  include ImageVariantsHelper

  test "transparent PNG becomes a resized WebP that keeps its alpha channel" do
    lesson = lessons(:intro)
    lesson.cover_image.attach(io: StringIO.new(transparent_png(2400, 1200)), filename: "cover.png", content_type: "image/png")

    variant = image_variant(lesson.cover_image, :large).processed
    image = Vips::Image.new_from_buffer(variant.download, "")

    assert_equal "image/webp", variant.image.blob.content_type
    assert_equal [ 1600, 800 ], [ image.width, image.height ]
    assert image.has_alpha?, "expected WebP variant to keep transparency"
    assert_equal 0, image[3].getpoint(10, 10).first.round, "left half should stay transparent"
    assert_equal 255, image[3].getpoint(1500, 10).first.round, "right half should stay opaque"
  end

  test "PNG sources use near-lossless WebP, other formats lossy" do
    png = ActiveStorage::Blob.new(content_type: "image/png")
    jpeg = ActiveStorage::Blob.new(content_type: "image/jpeg")

    assert_equal true, image_variant_transformations(png, :large)[:saver][:near_lossless]
    assert_nil image_variant_transformations(jpeg, :large)[:saver][:near_lossless]
    assert_equal :webp, image_variant_transformations(jpeg, :thumb)[:format]
  end

  test "GIFs are served as the original so animation is not lost" do
    user = users(:student)
    user.avatar.attach(io: StringIO.new(Vips::Image.black(4, 4).gifsave_buffer), filename: "a.gif", content_type: "image/gif")

    assert_same user.avatar, image_variant(user.avatar, :avatar)
  end

  test "an already web-ready upload is served as the original" do
    lesson = lessons(:intro)
    lesson.cover_image.attach(io: StringIO.new(transparent_png(1456, 640)), filename: "cover.png", content_type: "image/png")
    lesson.cover_image.blob.analyze

    assert_operator lesson.cover_image.blob.byte_size, :<, 200.kilobytes
    assert_same lesson.cover_image, image_variant(lesson.cover_image, :large)
  end

  test "web-ready needs small size, fitting dimensions, a web format and analysed metadata" do
    ready = { content_type: "image/jpeg", byte_size: 150.kilobytes, metadata: { "width" => 1456, "height" => 640 } }

    assert web_ready_image?(ActiveStorage::Blob.new(**ready), :large)
    assert_not web_ready_image?(ActiveStorage::Blob.new(**ready, byte_size: 250.kilobytes), :large), "too heavy"
    assert_not web_ready_image?(ActiveStorage::Blob.new(**ready, metadata: { "width" => 4000, "height" => 640 }), :large), "too wide"
    assert_not web_ready_image?(ActiveStorage::Blob.new(**ready, content_type: "image/tiff"), :large), "not a web format"
    assert_not web_ready_image?(ActiveStorage::Blob.new(**ready, metadata: {}), :large), "not analysed yet"
    assert_not web_ready_image?(ActiveStorage::Blob.new(**ready), :thumb), "fine as a cover, too big for a thumbnail"
  end

  private

  def transparent_png(width, height)
    rgb = Vips::Image.black(width, height, bands: 3) + [ 200, 80, 40 ]
    alpha = (Vips::Image.xyz(width, height)[0] > width / 2).ifthenelse(255, 0)
    rgb.bandjoin(alpha).cast(:uchar).copy(interpretation: :srgb).pngsave_buffer
  end
end
