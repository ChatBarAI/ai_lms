require "test_helper"

class GoogleGeminiClientTest < ActiveSupport::TestCase
  Configuration = Data.define(:api_key, :base_url, :model)

  test "sends a Gemini multimodal request and returns generated HTML" do
    configuration = Configuration.new(
      api_key: "gemini-secret",
      base_url: "https://generativelanguage.googleapis.com/v1beta",
      model: "gemini-2.5-flash"
    )
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.body = JSON.generate(
      responseId: "gemini_123",
      candidates: [ { content: { parts: [ { text: "```html\n<html>Designed</html>\n```" } ] } } ],
      usageMetadata: { promptTokenCount: 25, candidatesTokenCount: 12 }
    )
    response.instance_variable_set(:@read, true)
    captured_request = nil
    client = GoogleGeminiClient.new(configuration)

    client.stub(:perform_request, ->(_uri, request) { captured_request = request; response }) do
      image = AiProviderClient::ImageInput.new(
        name: "Draft", media_type: "image/png", data: "base64-data"
      )
      result = client.generate(
        system_prompt: "System rules", user_prompt: "Design this", design_references: [ image ]
      )

      assert_equal "<html>Designed</html>", result.html
      assert_equal "gemini_123", result.request_id
      assert_equal 25, result.input_tokens
      assert_equal 12, result.output_tokens
    end

    assert_equal "gemini-secret", captured_request["x-goog-api-key"]
    assert_equal "/v1beta/models/gemini-2.5-flash:generateContent", captured_request.path
    body = JSON.parse(captured_request.body)
    assert_equal "System rules", body.dig("systemInstruction", "parts", 0, "text")
    assert_equal 16_000, body.dig("generationConfig", "maxOutputTokens")
    parts = body.dig("contents", 0, "parts")
    assert_equal "Design reference image 1: Draft", parts[0]["text"]
    assert_equal "image/png", parts[1].dig("inlineData", "mimeType")
    assert_equal "base64-data", parts[1].dig("inlineData", "data")
    assert_equal "Design this", parts[2]["text"]
  end

  test "provider factory selects the Google Gemini client" do
    configuration = Struct.new(:provider).new("google")

    assert_instance_of GoogleGeminiClient, AiProviderClient.build(configuration)
  end
end
