require "base64"

class MaterialDesignGenerationService
  MAX_OUTPUT_TOKENS = 16_000
  MAX_IMAGE_COUNT = 12
  MAX_TOTAL_IMAGE_BYTES = 30.megabytes
  CONSERVATIVE_CHARACTERS_PER_TOKEN = 2
  ASSET_GROUNDING_PROMPT = <<~PROMPT.freeze
    ASSET RULES — THESE RULES ARE MANDATORY:
    - Images explicitly labelled as DESIGN REFERENCES are visual instructions. Analyze their layout,
      spacing, colors, typography, visual hierarchy, component styling, and visible text, then recreate
      that design with accessible HTML and CSS. Do not place the reference screenshot itself in the page.
    - Images and videos listed as CONTENT ASSETS are visual resources that may be placed in the generated page.
    - Video content assets are metadata only. Use their supplied asset:// token as the src of an
      accessible <video controls preload="metadata"> element. Never invent or use another video URL.
    - The design request, source HTML, and visible text in design references are the only sources of
      written content and factual meaning. Reference text may be reproduced when the request asks to
      recreate that design.
    - Content asset filenames, descriptions, alt text, and visual
      appearance must never be used to infer or introduce topics, facts, names, claims, examples,
      captions, headings, or body text.
    - Asset metadata exists only to help select and place an appropriate asset and to provide its
      alt attribute or accessible video context. Do not quote, paraphrase, expand upon, or otherwise
      turn it into page content.
    - Preserve assets marked as already referenced in the source HTML unless the design request
      explicitly asks to remove or replace them. Assets not referenced in the source are optional.
    - Do not add substantive written content that is absent from the design request, source HTML,
      and visible text in design references.
    - If an asset cannot be used without inventing context, omit it.
  PROMPT

  def initialize(revision, client: nil)
    @revision = revision
    @client = client || AiProviderClient.build(revision.ai_model_configuration)
  end

  def call
    unless revision.ai_model_configuration.enabled?
      raise AiProviderClient::Error, "The AI configuration is disabled"
    end

    update_status!(status: "generating", error_message: nil)
    ensure_assets_fit_budget!
    user_prompt = build_user_prompt
    ensure_prompt_fits_context!(user_prompt)
    result = client.generate(
      system_prompt: [
        revision.ai_model_configuration.effective_system_prompt,
        ASSET_GROUNDING_PROMPT
      ].join("\n\n"),
      user_prompt: user_prompt,
      design_references: design_reference_inputs,
      content_assets: content_asset_inputs
    )
    html_with_assets = result.html.dup
    asset_url_map.each { |token, url| html_with_assets.gsub!(token, url) }
    sanitized = SafeHtmlPolicy.sanitize_ai_document(
      html_with_assets,
      image_urls: asset_catalog.entries.select(&:image?).map(&:url),
      video_urls: asset_catalog.entries.select(&:video?).map(&:url)
    )
    raise AiProviderClient::Error, "The generated page was empty after sanitisation" if sanitized.blank?

    update_status!(
      status: "ready", generated_html: result.html, sanitized_html: sanitized,
      provider_request_id: result.request_id, input_tokens: result.input_tokens,
      output_tokens: result.output_tokens, error_message: nil
    )
  rescue StandardError => error
    revision.update_columns(status: "failed", error_message: error.message.to_s[0, 2_000], updated_at: Time.current)
    revision.reload.broadcast_status
    raise
  end

  private

  attr_reader :revision, :client

  def update_status!(attributes)
    revision.update!(attributes)
    revision.broadcast_status
  end

  def build_user_prompt
    <<~PROMPT
      DESIGN REQUEST
      #{revision.request}

      DESIGN REFERENCES
      #{design_reference_manifest.presence || "None."}

      CONTENT ASSETS
      The metadata below is for visual selection and placement only. It is not lesson content.
      #{asset_manifest.presence || "None. Do not add images or videos."}

      SOURCE HTML
      #{tokenized_source_html.presence || "No source HTML. Create the page from scratch."}
    PROMPT
  end

  def design_reference_manifest
    asset_catalog.design_references.map.with_index(1) do |asset, index|
      %(Reference image #{index}: #{asset.name}. Recreate its visual design; do not embed this screenshot.)
    end.join("\n")
  end

  def design_reference_inputs
    asset_catalog.design_references.map do |asset|
      AiProviderClient::ImageInput.new(
        name: asset.name,
        media_type: asset.file.blob.content_type,
        data: Base64.strict_encode64(asset.file.download)
      )
    end
  end

  def content_asset_inputs
    manual_inputs = revision.lesson_material.material_design_assets.content
      .includes(file_attachment: :blob).filter_map do |asset|
        image_input(asset.name, asset.file.blob) if asset.image?
      end
    imported_inputs = revision.lesson_material.imported_assets.attachments.includes(:blob).map do |attachment|
      image_input(attachment.blob.filename.to_s, attachment.blob)
    end
    manual_inputs + imported_inputs
  end

  def image_input(name, blob)
    AiProviderClient::ImageInput.new(
      name: name, media_type: blob.content_type, data: Base64.strict_encode64(blob.download)
    )
  end

  def asset_manifest
    asset_catalog.entries.map do |asset|
      usage = if asset.referenced_in_source
        "already referenced in source HTML: yes; preserve unless the design request says otherwise"
      else
        "already referenced in source HTML: no; optional visual resource"
      end
      kind = asset.video? ? "video" : "image"
      accessibility = asset.video? ? "accessible label" : "alt text"
      %(#{asset.token} — #{kind}: #{asset.name}; description: #{asset.description.presence || "not supplied"}; #{accessibility}: #{asset.alt_text.presence || "not supplied"}; #{usage})
    end.join("\n")
  end

  def asset_url_map
    @asset_url_map ||= asset_catalog.entries.to_h { |asset| [ asset.token, asset.url ] }
  end

  def asset_catalog
    @asset_catalog ||= MaterialDesignAssetCatalog.new(revision.lesson_material)
  end

  def tokenized_source_html
    source = revision.source_html.to_s
    return if source.blank?

    asset_catalog.tokenize_html(source)
  end

  def ensure_prompt_fits_context!(user_prompt)
    prompt_characters = revision.ai_model_configuration.effective_system_prompt.length +
                        ASSET_GROUNDING_PROMPT.length + user_prompt.length
    estimated_input_tokens = (prompt_characters.to_f / CONSERVATIVE_CHARACTERS_PER_TOKEN).ceil
    required_tokens = estimated_input_tokens + MAX_OUTPUT_TOKENS
    context_window = revision.ai_model_configuration.context_window_tokens
    return if required_tokens <= context_window

    raise AiProviderClient::Error,
          "The source is too large for this model: approximately #{estimated_input_tokens} input " \
          "tokens plus a #{MAX_OUTPUT_TOKENS}-token output reserve exceeds its " \
          "#{context_window}-token context window. Choose a model with a larger context window " \
          "or reduce the source HTML."
  end

  def ensure_assets_fit_budget!
    blobs = revision.lesson_material.material_design_assets
      .includes(file_attachment: :blob).filter_map { |asset| asset.file.blob if asset.image? }
    blobs.concat(revision.lesson_material.imported_assets.attachments.includes(:blob).map(&:blob))

    if blobs.size > MAX_IMAGE_COUNT
      raise AiProviderClient::Error,
            "Too many images for one generation (maximum #{MAX_IMAGE_COUNT})"
    end

    total_bytes = blobs.sum(&:byte_size)
    return if total_bytes <= MAX_TOTAL_IMAGE_BYTES

    raise AiProviderClient::Error,
          "Images exceed the #{MAX_TOTAL_IMAGE_BYTES / 1.megabyte} MB total limit for one generation"
  end
end
