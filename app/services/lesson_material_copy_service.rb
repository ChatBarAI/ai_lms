class LessonMaterialCopyService
  class CopyError < StandardError; end

  DIRECT_ATTACHMENTS = %i[document audio_file image_file video_file].freeze

  def initialize(source:, destination_lesson:, copied_by:, copy_settings: true)
    @source = source
    @destination_lesson = destination_lesson
    @copied_by = copied_by
    @copy_settings = copy_settings
    @created_blobs = []
    @html_replacements = {}
  end

  def call
    LessonMaterial.transaction do
      create_material!
      copy_direct_attachments!
      copy_imported_assets!
      copy_rich_text!
      copy_design_assets!
      rewrite_raw_html!
      material.save!
    end

    material
  rescue StandardError => error
    cleanup_created_blobs
    raise error if error.is_a?(CopyError)

    raise CopyError, "The material could not be copied: #{error.message}"
  end

  private

  attr_reader :source, :destination_lesson, :copied_by, :copy_settings, :material

  def create_material!
    @material = destination_lesson.lesson_materials.new(
      title: source.title,
      kind: source.kind,
      raw_html_content: source.raw_html_content,
      url: source.url,
      chatbar_token: source.chatbar_token,
      chatbar_prompt: source.chatbar_prompt,
      required: copy_settings ? source.required : true,
      open_by_default: copy_settings ? source.open_by_default : false,
      source_material: source,
      copied_by: copied_by,
      position: destination_lesson.lesson_materials.maximum(:position).to_i + 1
    )
    # Attachment-backed kinds cannot validate until their files have been copied.
    material.save!(validate: false)
  end

  def copy_direct_attachments!
    DIRECT_ATTACHMENTS.each do |name|
      source_attachment = source.public_send(name)
      next unless source_attachment.attached?

      material.public_send(name).attach(duplicate_blob(source_attachment.blob))
    end
  end

  def copy_imported_assets!
    source.imported_assets.attachments.includes(:blob).each do |attachment|
      new_blob = duplicate_blob(attachment.blob)
      material.imported_assets.attach(new_blob)
      register_blob_paths(attachment.blob, new_blob)
    end
  end

  def copy_rich_text!
    return unless source.body.present?

    html = source.body.body.to_html
    source.body.embeds.blobs.each do |blob|
      new_blob = duplicate_blob(blob)
      html = html.gsub(blob.attachable_sgid, new_blob.attachable_sgid)
    end
    material.body = html
  end

  def copy_design_assets!
    source.material_design_assets.includes(file_attachment: :blob).find_each do |asset|
      copy = material.material_design_assets.create!(
        name: asset.name,
        description: asset.description,
        alt_text: asset.alt_text,
        role: asset.role,
        created_by: copied_by,
        file: duplicate_blob(asset.file.blob)
      )
      register_design_asset_paths(asset, copy)
    end
  end

  def rewrite_raw_html!
    # The preliminary save happens before design assets are copied, so its sanitizer cannot yet
    # authorize asset-backed videos. Restore the source before rewriting every copied asset URL.
    material.raw_html_content = source.raw_html_content
    return if material.raw_html_content.blank? || @html_replacements.empty?

    rewritten = material.raw_html_content.dup
    @html_replacements.each { |old_value, new_value| rewritten.gsub!(old_value, new_value) }
    material.raw_html_content = rewritten
  end

  def duplicate_blob(blob)
    copy = blob.open do |file|
      ActiveStorage::Blob.create_and_upload!(
        io: file,
        filename: blob.filename,
        content_type: blob.content_type,
        identify: false
      )
    end
    @created_blobs << copy
    copy
  end

  def register_blob_paths(old_blob, new_blob)
    routes = Rails.application.routes.url_helpers
    %w[inline attachment].each do |disposition|
      old_path = routes.rails_storage_proxy_path(old_blob, disposition: disposition, only_path: true)
      new_path = routes.rails_storage_proxy_path(new_blob, disposition: disposition, only_path: true)
      @html_replacements[old_path] = new_path
    end
  end

  def register_design_asset_paths(old_asset, new_asset)
    routes = Rails.application.routes.url_helpers
    old_path = routes.material_design_asset_file_path(
      old_asset.signed_id(purpose: :material_design_asset), v: old_asset.file.blob_id
    )
    new_path = routes.material_design_asset_file_path(
      new_asset.signed_id(purpose: :material_design_asset), v: new_asset.file.blob_id
    )
    @html_replacements[old_path] = new_path
    legacy_old_path = routes.material_design_asset_file_path(
      old_asset.signed_id(purpose: :material_design_asset)
    )
    @html_replacements[legacy_old_path] = new_path
  end

  def cleanup_created_blobs
    @created_blobs.each do |blob|
      blob.purge if blob.persisted? && blob.attachments.empty?
    rescue StandardError
      Rails.logger.warn("Could not clean up blob #{blob.id} after failed material copy")
    end
  end
end
