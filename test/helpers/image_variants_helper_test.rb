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

  test "every preset converts to lossy WebP at Q80 with metadata stripped" do
    ImageVariantsHelper::IMAGE_VARIANT_PRESETS.each_key do |preset|
      transformations = image_variant_transformations(preset)

      assert_equal :webp, transformations[:format]
      assert_equal({ strip: true, Q: 80 }, transformations[:saver])
    end
  end

  test "a large photo saved as PNG shrinks well below 1 MB" do
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(noisy_png(3000, 2000)), filename: "photo.png", content_type: "image/png")
    assert_operator blob.byte_size, :>, 1.megabyte

    variant = image_variant(blob, :large).processed

    assert_operator variant.image.blob.byte_size, :<, 1.megabyte
    assert_operator variant.image.blob.byte_size, :<, blob.byte_size / 4
  end

  test "accepts a blob, as used for images in lesson text" do
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(transparent_png(2048, 1024)), filename: "body.png", content_type: "image/png")

    variant = image_variant(blob, :embed).processed
    image = Vips::Image.new_from_buffer(variant.download, "")

    assert_equal "image/webp", variant.image.blob.content_type
    assert_equal [ 1024, 512 ], [ image.width, image.height ]
  end

  test "the site logo is resized to the logo preset" do
    SiteSetting.current.logo.attach(io: StringIO.new(transparent_png(2000, 500)), filename: "logo.png", content_type: "image/png")

    image = Vips::Image.new_from_buffer(image_variant(SiteSetting.current.logo, :logo).processed.download, "")

    assert_equal [ 512, 128 ], [ image.width, image.height ]
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

  # Photo-like content: smooth noise doesn't compress well as PNG.
  def noisy_png(width, height)
    noise = Vips::Image.gaussnoise(width / 8, height / 8, mean: 128, sigma: 50).resize(8, kernel: :linear)
    noise.bandjoin([ noise * 0.8, noise * 0.6 ]).cast(:uchar).copy(interpretation: :srgb).pngsave_buffer
  end

  def transparent_png(width, height)
    rgb = Vips::Image.black(width, height, bands: 3) + [ 200, 80, 40 ]
    alpha = (Vips::Image.xyz(width, height)[0] > width / 2).ifthenelse(255, 0)
    rgb.bandjoin(alpha).cast(:uchar).copy(interpretation: :srgb).pngsave_buffer
  end
end
