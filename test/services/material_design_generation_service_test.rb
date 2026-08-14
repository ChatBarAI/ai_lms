require "test_helper"

class MaterialDesignGenerationServiceTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  FakeClient = Struct.new(:result) do
    attr_reader :system_prompt, :user_prompt, :design_references, :content_assets

    def generate(system_prompt:, user_prompt:, design_references: [], content_assets: [])
      @system_prompt = system_prompt
      @user_prompt = user_prompt
      @design_references = design_references
      @content_assets = content_assets
      raise "missing system prompt" if system_prompt.blank?
      raise "missing user prompt" if user_prompt.blank?

      result
    end
  end

  test "stores a sanitised revision without changing the material" do
    material = LessonMaterial.create!(
      lesson: lessons(:intro), title: "AI source", kind: :raw_html_iframe,
      raw_html_content: "<html><body><p>Original</p></body></html>"
    )
    configuration = AiModelConfiguration.create!(
      name: "Test model", provider: "openai", model: "test-model",
      base_url: "https://api.openai.com/v1", api_key: "secret"
    )
    revision = material.material_design_revisions.create!(
      ai_model_configuration: configuration, created_by: users(:instructor),
      request: "Redesign it", source_html: material.raw_html_content
    )
    result = OpenaiResponsesClient::Result.new(
      html: '<html><head><style>body{color:#123}</style></head><body><script>alert(1)</script><a href="https://example.com">Text</a></body></html>',
      request_id: "resp_1", input_tokens: 10, output_tokens: 20
    )

    client = FakeClient.new(result)
    assert_broadcasts(MaterialDesignRevision.stream_name_for(material.id), 2) do
      MaterialDesignGenerationService.new(revision, client: client).call
    end

    assert revision.reload.ready?
    assert_not_includes revision.sanitized_html, "<script"
    assert_not_includes revision.sanitized_html, "https://example.com"
    assert_includes revision.sanitized_html, "Text"
    assert_includes material.reload.raw_html_content, "Original"
    assert_includes client.system_prompt, "CONTENT ASSETS are visual resources"
    assert_includes client.system_prompt, "must never be used to infer or introduce"
    assert_not_includes client.user_prompt, "COURSE CONTEXT"
    assert_not_includes client.user_prompt, material.lesson.course.title
    assert_not_includes client.user_prompt, material.lesson.title
    assert_not_includes client.user_prompt, material.title
    assert_empty client.design_references
    assert_empty client.content_assets
  end

  test "sends design references as vision input and excludes them from content assets" do
    material = LessonMaterial.create!(
      lesson: lessons(:intro), title: "Visual reference", kind: :raw_html_iframe,
      raw_html_content: LessonMaterial::AI_DESIGN_STARTER_HTML
    )
    reference = material.material_design_assets.create!(
      created_by: users(:instructor), name: "Draft layout", role: :design_reference,
      file: Rack::Test::UploadedFile.new(
        Rails.root.join("test/fixtures/files/poster.png"), "image/png", true
      )
    )
    content_asset = material.material_design_assets.create!(
      created_by: users(:instructor), name: "Ruby logo", role: :content,
      file: Rack::Test::UploadedFile.new(
        Rails.root.join("test/fixtures/files/poster.png"), "image/png", true
      )
    )
    configuration = AiModelConfiguration.create!(
      name: "Vision model", provider: "anthropic", model: "vision-model",
      base_url: "https://api.anthropic.com/v1", api_key: "secret"
    )
    revision = material.material_design_revisions.create!(
      ai_model_configuration: configuration, created_by: users(:instructor),
      request: "Recreate this design"
    )
    client = FakeClient.new(
      OpenaiResponsesClient::Result.new(
        html: "<html><body><main>Designed</main></body></html>", request_id: "msg_1",
        input_tokens: 10, output_tokens: 20
      )
    )

    MaterialDesignGenerationService.new(revision, client: client).call

    assert_equal 1, client.design_references.size
    assert_equal reference.name, client.design_references.first.name
    assert_equal "image/png", client.design_references.first.media_type
    assert client.design_references.first.data.present?
    assert_equal 1, client.content_assets.size
    assert_equal content_asset.name, client.content_assets.first.name
    assert_equal "image/png", client.content_assets.first.media_type
    assert client.content_assets.first.data.present?
    assert_includes client.user_prompt, "Reference image 1: Draft layout"
    assert_not_includes client.user_prompt, reference.prompt_token
  end

  test "sends the complete source when it fits the configured context window" do
    marker = "Important lesson content after the large stylesheet"
    source = "<html><head><style>#{'a' * 110_000}</style></head><body><main>#{marker}</main></body></html>"
    material = LessonMaterial.create!(
      lesson: lessons(:intro), title: "Large source", kind: :raw_html_iframe,
      raw_html_content: source
    )
    configuration = AiModelConfiguration.create!(
      name: "Large-context model", provider: "openai", model: "test-model",
      base_url: "https://api.openai.com/v1", api_key: "secret", context_window_tokens: 128_000
    )
    revision = material.material_design_revisions.create!(
      ai_model_configuration: configuration, created_by: users(:instructor),
      request: "Remove the menu", source_html: source
    )
    client = FakeClient.new(
      OpenaiResponsesClient::Result.new(
        html: "<html><body><main>#{marker}</main></body></html>", request_id: "resp_large",
        input_tokens: 40_000, output_tokens: 100
      )
    )

    MaterialDesignGenerationService.new(revision, client: client).call

    assert_includes client.user_prompt, marker
    assert revision.reload.ready?
  end

  test "fails before calling the provider when the estimated request exceeds the context window" do
    source = "<html><body>#{'content ' * 10_000}</body></html>"
    material = LessonMaterial.create!(
      lesson: lessons(:intro), title: "Oversized source", kind: :raw_html_iframe,
      raw_html_content: source
    )
    configuration = AiModelConfiguration.create!(
      name: "Small-context model", provider: "openai", model: "test-model",
      base_url: "https://api.openai.com/v1", api_key: "secret", context_window_tokens: 17_000
    )
    revision = material.material_design_revisions.create!(
      ai_model_configuration: configuration, created_by: users(:instructor),
      request: "Remove the menu", source_html: source
    )
    client = FakeClient.new(nil)

    error = assert_raises(AiProviderClient::Error) do
      MaterialDesignGenerationService.new(revision, client: client).call
    end

    assert_includes error.message, "source is too large"
    assert_includes error.message, "17000-token context window"
    assert_nil client.user_prompt
    assert revision.reload.failed?
  end

  test "fails before calling the provider when there are too many images" do
    material = LessonMaterial.create!(
      lesson: lessons(:intro), title: "Image-heavy source", kind: :raw_html_iframe,
      raw_html_content: LessonMaterial::AI_DESIGN_STARTER_HTML
    )
    (MaterialDesignGenerationService::MAX_IMAGE_COUNT + 1).times do |index|
      material.material_design_assets.create!(
        created_by: users(:instructor), name: "Image #{index}",
        file: Rack::Test::UploadedFile.new(
          Rails.root.join("test/fixtures/files/poster.png"), "image/png", true
        )
      )
    end
    configuration = AiModelConfiguration.create!(
      name: "Vision model", provider: "openai", model: "test-model",
      base_url: "https://api.openai.com/v1", api_key: "secret"
    )
    revision = material.material_design_revisions.create!(
      ai_model_configuration: configuration, created_by: users(:instructor), request: "Redesign it"
    )
    client = FakeClient.new(nil)

    error = assert_raises(AiProviderClient::Error) do
      MaterialDesignGenerationService.new(revision, client: client).call
    end

    assert_includes error.message, "Too many images"
    assert_nil client.user_prompt
    assert revision.reload.failed?
  end

  test "estimates revision cost from provider token usage" do
    configuration = AiModelConfiguration.new(
      input_cost_cents_per_million_tokens: 250,
      output_cost_cents_per_million_tokens: 1_000
    )

    assert_equal BigDecimal("2.25"), configuration.estimated_cost_cents(
      input_tokens: 5_000, output_tokens: 1_000
    )
  end

  test "accepting a ready revision replaces the material and records acceptance" do
    material = LessonMaterial.create!(
      lesson: lessons(:intro), title: "AI acceptance", kind: :raw_html_iframe,
      raw_html_content: "<html><body>Before</body></html>"
    )
    configuration = AiModelConfiguration.create!(
      name: "Acceptance model", provider: "openai", model: "test-model",
      base_url: "https://api.openai.com/v1", api_key: "secret"
    )
    revision = material.material_design_revisions.create!(
      ai_model_configuration: configuration, created_by: users(:instructor),
      request: "Replace it", status: "ready",
      sanitized_html: "<html><body><h1>After</h1></body></html>"
    )

    revision.accept!

    assert revision.reload.accepted?
    assert revision.accepted_at.present?
    assert material.reload.raw_html_iframe?
    assert_includes material.raw_html_content, "After"
  end
end
