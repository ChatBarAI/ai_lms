require "test_helper"

class AnthropicMessagesClientTest < ActiveSupport::TestCase
  Configuration = Data.define(:api_key, :base_url, :model)

  test "sends an Anthropic Messages request and returns generated HTML" do
    configuration = Configuration.new(
      api_key: "anthropic-secret",
      base_url: "https://api.anthropic.com/v1",
      model: "claude-sonnet-4-20250514"
    )
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.body = JSON.generate(
      id: "msg_123",
      content: [ { type: "text", text: "```html\n<html><body>Designed</body></html>\n```" } ],
      usage: { input_tokens: 25, output_tokens: 12 }
    )
    response.instance_variable_set(:@read, true)
    captured_request = nil
    client = AnthropicMessagesClient.new(configuration)

    client.stub(:perform_request, ->(_uri, request) { captured_request = request; response }) do
      image = AiProviderClient::ImageInput.new(
        name: "Draft", media_type: "image/png", data: "base64-data"
      )
      result = client.generate(
        system_prompt: "System rules", user_prompt: "Design this", design_references: [ image ]
      )

      assert_equal "<html><body>Designed</body></html>", result.html
      assert_equal "msg_123", result.request_id
      assert_equal 25, result.input_tokens
      assert_equal 12, result.output_tokens
    end

    body = JSON.parse(captured_request.body)
    assert_equal "anthropic-secret", captured_request["x-api-key"]
    assert_equal "2023-06-01", captured_request["anthropic-version"]
    assert_equal "System rules", body["system"]
    assert_equal "user", body.dig("messages", 0, "role")
    content = body.dig("messages", 0, "content")
    assert_equal "Design reference image 1: Draft", content[0]["text"]
    assert_equal "image", content[1]["type"]
    assert_equal "base64", content[1].dig("source", "type")
    assert_equal "image/png", content[1].dig("source", "media_type")
    assert_equal "base64-data", content[1].dig("source", "data")
    assert_equal "Design this", content[2]["text"]
  end

  test "provider factory selects the Anthropic client" do
    configuration = Struct.new(:provider).new("anthropic")

    assert_instance_of AnthropicMessagesClient, AiProviderClient.build(configuration)
  end
end
