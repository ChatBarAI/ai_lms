# Serves uploaded images as resized WebP variants instead of the original file.
#
# Originals are kept untouched (downloads, "Open in new tab" and the cropper
# still use them); variants are generated lazily by Active Storage (vips) on
# first request and cached as their own blobs.
#
# Format rules:
#   - PNG, JPEG and WebP sources -> lossy WebP, quality 80. Transparency is
#     kept (WebP stores the alpha channel losslessly). Lossy is used for PNGs
#     too: many PNG uploads are photos (Canva/screenshot exports), where
#     near-lossless barely shrinks the file, and at Q80 text in screenshots
#     is indistinguishable from the original.
#   - GIF (may be animated), SVG and anything vips can't read -> original.
#   - Metadata (EXIF/GPS) is stripped.
module ImageVariantsHelper
  # Resize presets. "cover" types use object-cover/object-contain in the
  # views, so resize_to_limit keeps the current look; small fixed boxes use
  # resize_to_fill at 2x their CSS size.
  IMAGE_VARIANT_PRESETS = {
    large:   { resize_to_limit: [ 1600, 1600 ] }, # cards, cover images, posters, image materials
    thumb:   { resize_to_fill: [ 128, 96 ] },     # 64x48 list thumbnails
    avatar:  { resize_to_fill: [ 160, 160 ] },    # up to 80x80 avatars
    logo:    { resize_to_limit: [ 640, 128 ] },   # site logo, shown up to 40px tall
    embed:   { resize_to_limit: [ 1024, 768 ] },  # images in lesson text (Rails' Action Text size)
    gallery: { resize_to_limit: [ 800, 600 ] }    # Action Text gallery images
  }.freeze

  PASSTHROUGH_IMAGE_TYPES = %w[image/gif image/svg+xml].freeze

  # An upload that already fits within these bounds is "web-ready" and is
  # served as-is: converting an image someone has already optimised (e.g. in
  # Squoosh) saves almost nothing and adds a second round of compression.
  WEB_READY_LIMITS = {
    large:   { max_dimensions: [ 1600, 1600 ], max_bytes: 200.kilobytes },
    thumb:   { max_dimensions: [ 256, 256 ],   max_bytes: 30.kilobytes },
    avatar:  { max_dimensions: [ 320, 320 ],   max_bytes: 50.kilobytes },
    logo:    { max_dimensions: [ 640, 128 ],   max_bytes: 50.kilobytes },
    embed:   { max_dimensions: [ 1024, 768 ],  max_bytes: 150.kilobytes },
    gallery: { max_dimensions: [ 800, 600 ],   max_bytes: 100.kilobytes }
  }.freeze

  WEB_READY_TYPES = %w[image/png image/jpeg image/webp].freeze

  # Accepts an attachment (has_one_attached), a blob, or the
  # ActionText::Attachment wrapper that Action Text passes to the blob partial.
  def image_variant(attachment, preset)
    attachment = attachment.attachable if attachment.is_a?(ActionText::Attachment)
    blob = attachment.is_a?(ActiveStorage::Blob) ? attachment : attachment.try(:blob)
    return attachment if blob.nil? || !blob.variable? || PASSTHROUGH_IMAGE_TYPES.include?(blob.content_type)
    return attachment if web_ready_image?(blob, preset)

    attachment.variant(**image_variant_transformations(preset))
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

  def image_variant_transformations(preset)
    IMAGE_VARIANT_PRESETS.fetch(preset).merge(format: :webp, saver: { strip: true, Q: 80 })
  end
end
