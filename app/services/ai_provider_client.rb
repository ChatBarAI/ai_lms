class AiProviderClient
  class Error < StandardError; end

  Result = Data.define(:html, :request_id, :input_tokens, :output_tokens)
  ImageInput = Data.define(:name, :media_type, :data)

  def self.build(configuration)
    case configuration.provider
    when "openai"
      OpenaiResponsesClient.new(configuration)
    when "anthropic"
      AnthropicMessagesClient.new(configuration)
    when "google"
      GoogleGeminiClient.new(configuration)
    when "mistral"
      MistralChatClient.new(configuration)
    else
      raise Error, "Unsupported AI provider: #{configuration.provider}"
    end
  end
end
