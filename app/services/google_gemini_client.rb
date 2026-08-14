require "net/http"
require "json"

class GoogleGeminiClient
  Error = AiProviderClient::Error
  Result = AiProviderClient::Result

  def initialize(configuration)
    @configuration = configuration
  end

  def generate(system_prompt:, user_prompt:, design_references: [], content_assets: [])
    raise Error, "The AI configuration has no API key" if configuration.api_key.blank?

    uri = URI("#{configuration.base_url.chomp('/')}/models/#{configuration.model}:generateContent")
    request = Net::HTTP::Post.new(uri)
    request["x-goog-api-key"] = configuration.api_key
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(
      systemInstruction: { parts: [ { text: system_prompt } ] },
      contents: [ { role: "user", parts: user_parts(user_prompt, design_references, content_assets) } ],
      generationConfig: { maxOutputTokens: 16_000 }
    )

    response = perform_request(uri, request)
    payload = JSON.parse(response.body)
    unless response.is_a?(Net::HTTPSuccess)
      raise Error, payload.dig("error", "message").presence || "AI provider returned HTTP #{response.code}"
    end

    html = payload.fetch("candidates", []).flat_map { |candidate| candidate.dig("content", "parts") || [] }
                  .filter_map { |part| part["text"] }.join("\n").strip
    raise Error, "AI provider returned no HTML" if html.blank?

    Result.new(
      html: strip_markdown_fence(html), request_id: payload["responseId"],
      input_tokens: payload.dig("usageMetadata", "promptTokenCount"),
      output_tokens: payload.dig("usageMetadata", "candidatesTokenCount")
    )
  rescue JSON::ParserError
    raise Error, "AI provider returned invalid JSON"
  rescue Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError => error
    raise Error, "AI provider request failed: #{error.message}"
  end

  private

  attr_reader :configuration

  def user_parts(user_prompt, design_references, content_assets)
    labelled_images(design_references, "Design reference") +
      labelled_images(content_assets, "Content asset") + [ { text: user_prompt } ]
  end

  def labelled_images(images, label)
    images.each_with_index.flat_map do |image, index|
      [
        { text: "#{label} image #{index + 1}: #{image.name}" },
        { inlineData: { mimeType: image.media_type, data: image.data } }
      ]
    end
  end

  def perform_request(uri, request)
    Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 180) do |http|
      http.request(request)
    end
  end

  def strip_markdown_fence(value)
    value.sub(/\A```(?:html)?\s*/i, "").sub(/\s*```\z/, "")
  end
end
