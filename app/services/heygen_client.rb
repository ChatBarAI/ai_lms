require "json"
require "net/http"
require "tempfile"
require "uri"

class HeygenClient
  class Error < StandardError; end

  DEFAULT_BASE_URL = ENV.fetch("HEYGEN_BASE_URL", "https://api.heygen.com").freeze
  ALLOWED_HOSTS = %w[api.heygen.com files.heygen.com].freeze

  def initialize(api_key:, base_url: DEFAULT_BASE_URL)
    @api_key = api_key.to_s.strip
    @base_url = base_url
    raise Error, "Missing HeyGen API key" if @api_key.empty?
  end

  def video(video_id)
    normalized = video_id.to_s.strip
    raise Error, "Missing video id" if normalized.empty?
    escaped_id = URI.encode_www_form_component(normalized)

    begin
      body = get_json(build_uri("/v2/videos/#{escaped_id}"))
      payload = unwrap_data(body)
      payload["id"] ||= normalized
      payload
    rescue Error => v2_error
      begin
        # Fallback for older API shape.
        body = get_json(build_uri("/v1/video_status.get?video_id=#{escaped_id}"))
        payload = unwrap_data(body)
        payload["id"] ||= normalized
        payload
      rescue Error
        raise v2_error
      end
    end
  end

  def download_video(video_payload)
    status = video_payload["status"].to_s
    unless complete_status?(status)
      raise Error, "HeyGen video is still #{status.tr('_', ' ').presence || 'processing'}"
    end

    download_url = video_payload["video_url"].to_s
    raise Error, "HeyGen video did not include a download URL" if download_url.empty?

    uri = URI.parse(download_url)
    filename = build_filename(video_payload, uri)
    content_type = content_type_for(uri)

    download_to_tempfile(uri) do |file|
      yield file, filename: filename, content_type: content_type
    end
  end

  private

  def build_uri(path)
    uri = URI.join(@base_url, path)
    unless %w[http https].include?(uri.scheme) &&
           (ALLOWED_HOSTS.include?(uri.host) || @base_url != DEFAULT_BASE_URL)
      raise Error, "Refusing to call non-allowlisted host: #{uri.host}"
    end
    uri
  end

  def get_json(uri)
    JSON.parse(get(uri))
  rescue JSON::ParserError => e
    raise Error, "Invalid JSON from HeyGen: #{e.message}"
  end

  def get(uri)
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 30) do |http|
      request = Net::HTTP::Get.new(uri.request_uri)
      request["X-Api-Key"] = @api_key
      request["Accept"] = "application/json"

      response = http.request(request)
      case response
      when Net::HTTPSuccess
        response.body
      else
        raise Error, "HeyGen API error #{response.code}: #{response.body.to_s[0, 200]}"
      end
    end
  rescue SocketError, Errno::ECONNREFUSED, Errno::ETIMEDOUT, Net::OpenTimeout, Net::ReadTimeout => e
    raise Error, "HeyGen API network error: #{e.class}: #{e.message}"
  end

  def download_to_tempfile(uri)
    file = Tempfile.new([ "heygen-video", File.extname(uri.path).presence || ".mp4" ], binmode: true)

    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 120) do |http|
      request = Net::HTTP::Get.new(uri.request_uri)
      request["X-Api-Key"] = @api_key if ALLOWED_HOSTS.include?(uri.host)

      http.request(request) do |response|
        case response
        when Net::HTTPSuccess
          response.read_body { |chunk| file.write(chunk) }
        else
          file.close!
          raise Error, "HeyGen download error #{response.code}: #{response.body.to_s[0, 200]}"
        end
      end
    end

    file.rewind
    yield file
  ensure
    file.close! if file && !file.closed?
  end

  def unwrap_data(body)
    data = body["data"].is_a?(Hash) ? body["data"] : body
    raise Error, "HeyGen response did not include video data" unless data.is_a?(Hash)

    data
  end

  def complete_status?(status)
    %w[completed complete success done].include?(status.to_s.downcase)
  end

  def build_filename(video_payload, uri)
    title = video_payload["title"].to_s.parameterize
    extension = File.extname(uri.path).presence || ".mp4"
    base = title.presence || "heygen-video-#{video_payload['id']}"
    "#{base}#{extension}"
  end

  def content_type_for(uri)
    case File.extname(uri.path).downcase
    when ".webm"
      "video/webm"
    when ".ogg"
      "video/ogg"
    else
      "video/mp4"
    end
  end
end
