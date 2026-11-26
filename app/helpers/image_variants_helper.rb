# Serves uploaded images as resized WebP variants instead of the original file.
#
# Originals are kept untouched (downloads, "Open in new tab" and the cropper
# still use them); variants are generated lazily by Active Storage (vips) on
# first request and cached as their own blobs.
#
# Format rules:
#   - JPEG / WebP sources -> lossy WebP, quality 80.
#   - PNG sources         -> near-lossless WebP, so screenshots and text stay
#                            sharp. Transparency is preserved in both modes.
#   - GIF (may be animated), SVG and anything vips can't read -> original.
#   - Metadata (EXIF/GPS) is stripped.
module ImageVariantsHelper
  # Resize presets. "cover" types use object-cover/object-contain in the
  # views, so resize_to_limit keeps the current look; small fixed boxes use
  # resize_to_fill at 2x their CSS size.
  IMAGE_VARIANT_PRESETS = {
    large:  { resize_to_limit: [ 1600, 1600 ] }, # cards, cover images, posters, image materials
    thumb:  { resize_to_fill: [ 128, 96 ] },     # 64x48 list thumbnails
    avatar: { resize_to_fill: [ 160, 160 ] }     # up to 80x80 avatars
  }.freeze

  PASSTHROUGH_IMAGE_TYPES = %w[image/gif image/svg+xml].freeze

  # An upload that already fits within these bounds is "web-ready" and is
  # served as-is: converting an image someone has already optimised (e.g. in
  # Squoosh) saves almost nothing and adds a second round of compression.
  WEB_READY_LIMITS = {
    large:  { max_dimensions: [ 1600, 1600 ], max_bytes: 200.kilobytes },
    thumb:  { max_dimensions: [ 256, 256 ],   max_bytes: 30.kilobytes },
    avatar: { max_dimensions: [ 320, 320 ],   max_bytes: 50.kilobytes }
  }.freeze

  WEB_READY_TYPES = %w[image/png image/jpeg image/webp].freeze

  def image_variant(attachment, preset)
    blob = attachment.try(:blob)
    return attachment if blob.nil? || !blob.variable? || PASSTHROUGH_IMAGE_TYPES.include?(blob.content_type)
    return attachment if web_ready_image?(blob, preset)

    attachment.variant(**image_variant_transformations(blob, preset))
  end

  # Relies on the width/height recorded when Active Storage analysed the
  # upload; until analysis has run we can't tell, so the variant is used.
  def web_ready_image?(blob, preset)
    limits = WEB_READY_LIMITS.fetch(preset)
    width = blob.metadata["width"]
    height = blob.metadata["height"]
    return false unless WEB_READY_TYPES.include?(blob.content_type) && width && height

    max_width, max_height = limits[:max_dimensions]
    blob.byte_size <= limits[:max_bytes] && width <= max_width && height <= max_height
  end

  def image_variant_transformations(blob, preset)
    saver = { strip: true }
    saver.merge!(blob.content_type == "image/png" ? { near_lossless: true, Q: 80 } : { Q: 80 })

    IMAGE_VARIANT_PRESETS.fetch(preset).merge(format: :webp, saver: saver)
  end
end
