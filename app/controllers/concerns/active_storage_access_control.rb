# Active Storage serves blobs from signed URLs by default. Those URLs are hard to
# guess, but anyone who has a valid URL can normally load the file. This concern
# makes LMS content assets follow the same visibility rules as their owning
# course instead:
#
# - SiteSetting assets, such as logos and favicons, stay public.
# - Course, Lesson, LessonMaterial, and their Trix/Action Text attachments are
#   public only when the owning course is published, has public access enabled,
#   and site-wide guest access is enabled.
# - Unknown attachment owners are protected by default.
#
# The concern is mixed into the Rails Active Storage controllers from
# config/initializers/active_storage_access_control.rb.
module ActiveStorageAccessControl
  extend ActiveSupport::Concern

  included do
    prepend_before_action :authenticate_user_for_protected_active_storage!
    after_action :mark_protected_active_storage_response_private!
  end

  private

  def authenticate_user_for_protected_active_storage!
    # Direct uploads create unattached blobs, so there is no owner record to
    # inspect. Only signed-in users may create uploads.
    if is_a?(ActiveStorage::DirectUploadsController)
      @protected_active_storage_request = true
      return require_active_storage_user!
    end

    blob = active_storage_blob_for_request
    return if blob.blank?

    return if public_active_storage_blob?(blob)

    @protected_active_storage_request = true
    require_active_storage_user!
  end

  def mark_protected_active_storage_response_private!
    return unless @protected_active_storage_request

    response.headers["Cache-Control"] = "private, no-store"
    response.headers["Pragma"] = "no-cache"
  end

  def active_storage_blob_for_request
    return instance_variable_get(:@blob) if instance_variable_defined?(:@blob)

    signed_id = params[:signed_blob_id] || params[:signed_id]
    return if signed_id.blank?

    ActiveStorage::Blob.find_signed!(signed_id)
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end

  def require_active_storage_user!
    return if user_signed_in?

    # Do not call Devise's authenticate_user! here: Active Storage controllers do
    # not run through the normal Devise failure app, which can turn Warden throws
    # into 500s. A plain 401 is the right response for denied file requests.
    head :unauthorized
  end

  def public_active_storage_blob?(blob)
    attachments = blob.attachments.includes(:record).to_a
    return false if attachments.empty?

    attachments.none? { |attachment| protected_active_storage_attachment?(attachment) }
  end

  def protected_active_storage_attachment?(attachment)
    record = attachment.record

    case record
    when SiteSetting
      false
    when Course, Lesson, LessonMaterial
      !record.public_to_guests?
    when ActionText::RichText
      # Trix embeds are attached to ActionText::RichText, not directly to the
      # lesson/material model. Follow the rich text record back to its owner.
      !rich_text_record_public_to_guests?(record)
    else
      true
    end
  end

  def rich_text_record_public_to_guests?(rich_text)
    return false unless %w[Lesson LessonMaterial].include?(rich_text.record_type)

    rich_text.record&.public_to_guests?
  end
end
