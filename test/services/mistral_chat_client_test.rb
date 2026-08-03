require "test_helper"

class MistralChatClientTest < ActiveSupport::TestCase
  Configuration = Data.define(:api_key, :base_url, :model)

  test "sends a Mistral multimodal request and returns generated HTML" do
    configuration = Configuration.new(
      api_key: "mistral-secret", base_url: "https://api.mistral.ai/v1", model: "mistral-small-latest"
    )
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.body = JSON.generate(
      id: "mistral_123",
      choices: [ { message: { content: "```html\n<html>Designed</html>\n```" } } ],
      usage: { prompt_tokens: 25, completion_tokens: 12 }
    )
    response.instance_variable_set(:@read, true)
    captured_request = nil
    client = MistralChatClient.new(configuration)

    client.stub(:perform_request, ->(_uri, request) { captured_request = request; response }) do
      image = AiProviderClient::ImageInput.new(
        name: "Draft", media_type: "image/png", data: "base64-data"
      )
      result = client.generate(
        system_prompt: "System rules", user_prompt: "Design this", design_references: [ image ]
      )

      assert_equal "<html>Designed</html>", result.html
      assert_equal "mistral_123", result.request_id
      assert_equal 25, result.input_tokens
      assert_equal 12, result.output_tokens
    end

    assert_equal "Bearer mistral-secret", captured_request["Authorization"]
    body = JSON.parse(captured_request.body)
    assert_equal "System rules", body.dig("messages", 0, "content")
    content = body.dig("messages", 1, "content")
    assert_equal "Design reference image 1: Draft", content[0]["text"]
    assert_equal "data:image/png;base64,base64-data", content[1]["image_url"]
    assert_equal "Design this", content[2]["text"]
  end

  test "provider factory selects the Mistral client" do
    configuration = Struct.new(:provider).new("mistral")

    assert_instance_of MistralChatClient, AiProviderClient.build(configuration)
  end
end
