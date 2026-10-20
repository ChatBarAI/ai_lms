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
    :material_layout,
    :published_at,
    :pass_mark,
    :duration_minutes,
    :cover_image,
    :retry_incorrect_only,
    :ratings_enabled,
    :free_text_pass_level,
    { tag_ids: [], section_order: [] }
  ].freeze

  STRIPPED_OPTIONAL_ATTRIBUTES = [
    :cbai_api_key,
    :anam_api_key,
    :anam_persona_id,
    :custom_tutor_embed_url,
    :custom_tutor_embed_script
  ].freeze

  # Rendered masked and blank on the form, so a blank submission keeps the saved value.
  SECRET_ATTRIBUTES = %w[cbai_api_key anam_api_key].freeze

  def initialize(lesson:, params:, allow_custom_tutor_script: false)
    @lesson = lesson
    @params = params
    @allow_custom_tutor_script = allow_custom_tutor_script
  end

  def call
    unless custom_tutor_script_allowed?
      @lesson.errors.add(:custom_tutor_embed_script, "can only be configured by an administrator")
      return false
    end

    attrs = normalized_attributes
    @lesson.assign_attributes(attrs)
    sync_cbai_details(attrs)
    anam_credentials_valid?
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
    SECRET_ATTRIBUTES.each do |attribute|
      if remove_secret?(attribute) && attrs[attribute].nil?
        attrs[attribute] = nil
      elsif attrs.key?(attribute) && attrs[attribute].nil?
        attrs.delete(attribute)
      end
    end

    clear_inactive_custom_tutor_embed(attrs)
    attrs
  end

  # The form's "Remove saved key" box; a newly entered key still wins.
  def remove_secret?(attribute)
    ActiveModel::Type::Boolean.new.cast(lesson_input[:"remove_#{attribute}"]) == true
  end

  def lesson_params
    lesson_input.permit(*PERMITTED_ATTRIBUTES)
  end

  def lesson_input
    @lesson_input ||= @params.require(:lesson)
  end

  def clear_inactive_custom_tutor_embed(attrs)
    return unless attrs["ai_tutor_provider"] == "custom"
    return unless attrs.key?("custom_tutor_embed_type")

    if attrs["custom_tutor_embed_type"] == "script"
      attrs["custom_tutor_embed_url"] = nil
    else
      attrs["custom_tutor_embed_script"] = nil
    end
  end

  def custom_tutor_script_allowed?
    return true if @allow_custom_tutor_script

    !lesson_input.key?(:custom_tutor_embed_script) &&
      lesson_input[:custom_tutor_embed_type] != "script"
  end

  def sync_cbai_details(attrs)
    return unless attrs.key?("cbai_api_key") && attrs["cbai_api_key"].present?

    details = CbaiClient.new(api_key: attrs["cbai_api_key"]).details
    @lesson.cbai_token = extract_cbai_token(details)
    @lesson.cbai_id = extract_cbai_id(details)
  end

  def anam_credentials_valid?
    return true unless @lesson.ai_tutor_provider_or_default == "anam"
    return true unless @lesson.anam_api_key_changed? || @lesson.anam_persona_id_changed? || @lesson.ai_tutor_provider_changed?

    key = @lesson.anam_api_key
    persona_id = @lesson.anam_persona_id
    return true if key.blank? && persona_id.blank?

    @lesson.errors.add(:anam_api_key, "can't be blank when an Anam persona ID is set") if key.blank?
    @lesson.errors.add(:anam_persona_id, "can't be blank when an Anam API key is set") if persona_id.blank?
    return false if @lesson.errors.any?

    AnamClient.new(api_key: key).verify_persona!(persona_id)
    true
  rescue AnamClient::InvalidPersona => e
    @lesson.errors.add(:anam_persona_id, "could not be verified: #{e.message}")
    false
  rescue AnamClient::Error => e
    # A blank submission keeps the saved key, so say which key failed and how to fix it.
    message = if @lesson.anam_api_key_changed?
      "could not be verified: #{e.message}"
    else
      "saved for this lesson could not be verified: #{e.message}. Enter a valid key, or choose another AI tutor provider"
    end
    @lesson.errors.add(:anam_api_key, message)
    false
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
