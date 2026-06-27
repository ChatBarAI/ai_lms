class LessonFormAssignmentService
  PERMITTED_ATTRIBUTES = [
    :title,
    :position,
    :body,
    :ai_tutor_provider,
    :cbai_display_mode,
    :custom_tutor_embed_url,
    :custom_tutor_embed_type,
    :custom_tutor_embed_script,
    :quiz_layout,
    :published_at,
    :pass_mark,
    :duration_minutes,
    :cover_image,
    :retry_incorrect_only,
    :ratings_enabled,
    :free_text_pass_level,
    { tag_ids: [] }
  ].freeze

  STRIPPED_OPTIONAL_ATTRIBUTES = [
    :cbai_api_key,
    :anam_api_key,
    :anam_persona_id,
    :custom_tutor_embed_url,
    :custom_tutor_embed_script
  ].freeze

  def initialize(lesson:, params:)
    @lesson = lesson
    @params = params
  end

  def call
    attrs = normalized_attributes
    @lesson.assign_attributes(attrs)
    sync_cbai_details(attrs)
    true
  rescue CbaiClient::Error => e
    @lesson.errors.add(:cbai_api_key, "could not load ChatBar AI details: #{e.message}")
    false
  end

  private

  def normalized_attributes
    attrs = lesson_params.to_h

    STRIPPED_OPTIONAL_ATTRIBUTES.each do |attribute|
      next unless lesson_input.key?(attribute)

      attrs[attribute.to_s] = lesson_input[attribute].to_s.strip.presence
    end

    clear_inactive_custom_tutor_embed(attrs)
    attrs
  end

  def lesson_params
    lesson_input.permit(*PERMITTED_ATTRIBUTES)
  end

  def lesson_input
    @lesson_input ||= @params.require(:lesson)
  end

  def clear_inactive_custom_tutor_embed(attrs)
    return unless attrs["ai_tutor_provider"] == "custom"

    if attrs["custom_tutor_embed_type"] == "script"
      attrs["custom_tutor_embed_url"] = nil
    else
      attrs["custom_tutor_embed_script"] = nil
    end
  end

  def sync_cbai_details(attrs)
    return unless attrs.key?("cbai_api_key") && attrs["cbai_api_key"].present?

    details = CbaiClient.new(api_key: attrs["cbai_api_key"]).details
    @lesson.cbai_token = extract_cbai_token(details)
    @lesson.cbai_id = extract_cbai_id(details)
  end

  def extract_cbai_token(details)
    token = details["token"].presence || details["cbai_token"].presence || details.dig("cbai", "token").presence
    raise CbaiClient::Error, "CBAI details did not include a token" if token.blank?

    token
  end

  def extract_cbai_id(details)
    raw = details["id"] || details["cbai_id"] || details.dig("cbai", "id")
    Integer(raw) if raw.present?
  rescue ArgumentError, TypeError
    nil
  end
end
