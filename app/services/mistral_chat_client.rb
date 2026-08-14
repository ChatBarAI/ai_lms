require "net/http"
require "json"

class MistralChatClient
  Error = AiProviderClient::Error
  Result = AiProviderClient::Result

  def initialize(configuration)
    @configuration = configuration
  end

  def generate(system_prompt:, user_prompt:, design_references: [], content_assets: [])
    raise Error, "The AI configuration has no API key" if configuration.api_key.blank?

    uri = URI.join(configuration.base_url.chomp("/") + "/", "chat/completions")
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{configuration.api_key}"
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(
      model: configuration.model,
      messages: [
        { role: "system", content: system_prompt },
        { role: "user", content: user_content(user_prompt, design_references, content_assets) }
      ],
      max_tokens: 16_000
    )

    response = perform_request(uri, request)
    payload = JSON.parse(response.body)
    unless response.is_a?(Net::HTTPSuccess)
      raise Error, payload.dig("message").presence || payload.dig("error", "message").presence ||
                   "AI provider returned HTTP #{response.code}"
    end

    content = payload.dig("choices", 0, "message", "content")
    html = if content.is_a?(Array)
      content.filter_map { |part| part["text"] if part["type"] == "text" }.join("\n").strip
    else
      content.to_s.strip
    end
    raise Error, "AI provider returned no HTML" if html.blank?

    Result.new(
      html: strip_markdown_fence(html), request_id: payload["id"],
      input_tokens: payload.dig("usage", "prompt_tokens"),
      output_tokens: payload.dig("usage", "completion_tokens")
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
        { type: "image_url", image_url: "data:#{image.media_type};base64,#{image.data}" }
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
