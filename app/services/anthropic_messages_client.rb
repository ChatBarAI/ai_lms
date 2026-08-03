require "net/http"
require "json"

class AnthropicMessagesClient
  Error = AiProviderClient::Error
  Result = AiProviderClient::Result

  def initialize(configuration)
    @configuration = configuration
  end

  def generate(system_prompt:, user_prompt:, design_references: [], content_assets: [])
    raise Error, "The AI configuration has no API key" if configuration.api_key.blank?

    uri = URI.join(configuration.base_url.chomp("/") + "/", "messages")
    request = Net::HTTP::Post.new(uri)
    request["x-api-key"] = configuration.api_key
    request["anthropic-version"] = "2023-06-01"
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(
      model: configuration.model,
      system: system_prompt,
      messages: [ { role: "user", content: user_content(user_prompt, design_references, content_assets) } ],
      max_tokens: 16_000
    )

    response = perform_request(uri, request)
    payload = JSON.parse(response.body)
    unless response.is_a?(Net::HTTPSuccess)
      raise Error, payload.dig("error", "message").presence || "AI provider returned HTTP #{response.code}"
    end

    html = payload.fetch("content", [])
                  .filter_map { |content| content["text"] if content["type"] == "text" }
                  .join("\n").strip
    raise Error, "AI provider returned no HTML" if html.blank?

    Result.new(
      html: strip_markdown_fence(html), request_id: payload["id"],
      input_tokens: payload.dig("usage", "input_tokens"),
      output_tokens: payload.dig("usage", "output_tokens")
    )
  rescue JSON::ParserError
    raise Error, "AI provider returned invalid JSON"
  rescue Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError => error
    raise Error, "AI provider request failed: #{error.message}"
  end

  private

  attr_reader :configuration

  def user_content(user_prompt, design_references, content_assets)
    labelled_images(design_references, "Design reference") +
      labelled_images(content_assets, "Content asset") + [ { type: "text", text: user_prompt } ]
  end

  def labelled_images(images, label)
    images.each_with_index.flat_map do |image, index|
      [
        { type: "text", text: "#{label} image #{index + 1}: #{image.name}" },
        {
          type: "image",
          source: { type: "base64", media_type: image.media_type, data: image.data }
        }
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
