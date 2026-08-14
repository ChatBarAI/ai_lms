require "test_helper"

class OpenaiResponsesClientTest < ActiveSupport::TestCase
  Configuration = Data.define(:api_key, :base_url, :model)

  test "sends design references as Responses API image input" do
    configuration = Configuration.new(
      api_key: "openai-secret", base_url: "https://api.openai.com/v1", model: "vision-model"
    )
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.body = JSON.generate(
      id: "resp_123",
      output: [ { content: [ { type: "output_text", text: "<html>Designed</html>" } ] } ],
      usage: { input_tokens: 25, output_tokens: 12 }
    )
    response.instance_variable_set(:@read, true)
    captured_request = nil
    http = Object.new
    http.define_singleton_method(:request) do |request|
      captured_request = request
      response
    end
    image = AiProviderClient::ImageInput.new(
      name: "Draft", media_type: "image/png", data: "base64-data"
    )

    http_start = ->(*_args, &block) { block.call(http) }
    Net::HTTP.stub(:start, http_start) do
      result = OpenaiResponsesClient.new(configuration).generate(
        system_prompt: "System rules", user_prompt: "Design this", design_references: [ image ]
      )

      assert_equal "<html>Designed</html>", result.html
    end

    body = JSON.parse(captured_request.body)
    assert_equal "Bearer openai-secret", captured_request["Authorization"]
    content = body.dig("input", 1, "content")
    assert_equal "Design this", content[0]["text"]
    assert_equal "Design reference image 1: Draft", content[1]["text"]
    assert_equal "input_image", content[2]["type"]
    assert_equal "data:image/png;base64,base64-data", content[2]["image_url"]
    assert_equal "high", content[2]["detail"]
  end
end
