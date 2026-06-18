require "json"
require "net/http"
require "tempfile"
require "uri"

class SynthesiaClient
  class Error < StandardError; end

  DEFAULT_BASE_URL = ENV.fetch("SYNTHESIA_BASE_URL", "https://api.synthesia.io").freeze
  ALLOWED_HOSTS = %w[api.synthesia.io].freeze

  def initialize(api_key:, base_url: DEFAULT_BASE_URL)
    @api_key = api_key.to_s.strip
    @base_url = base_url
    raise Error, "Missing Synthesia API key" if @api_key.empty?
  end

  def videos(limit: 20, offset: 0, source: %w[workspace shared_with_me my_videos])
    uri = build_uri("/v2/videos")
    uri.query = URI.encode_www_form({ limit: limit, offset: offset, source: source }.to_a.flat_map { |key, value| Array(value).map { |item| [ key, item ] } })
    body = get_json(uri)
    body.fetch("videos")
  rescue KeyError
    raise Error, "Synthesia response did not include videos"
  end

  def video(video_id)
    get_json(build_uri("/v2/videos/#{video_id}"))
  end

  def download_video(video_payload)
    download_url = video_payload["download"].to_s
    status = video_payload["status"].to_s

    raise Error, "Synthesia video is still #{status.tr('_', ' ')}" if status.present? && status != "complete"
    raise Error, "Synthesia video did not include a download URL" if download_url.empty?

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
    raise Error, "Invalid JSON from Synthesia: #{e.message}"
  end

  def get(uri)
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 30) do |http|
      request = Net::HTTP::Get.new(uri.request_uri)
      request["Authorization"] = @api_key
      request["Accept"] = "application/json"

      response = http.request(request)
      case response
      when Net::HTTPSuccess
        response.body
      else
        raise Error, "Synthesia API error #{response.code}: #{response.body.to_s[0, 200]}"
      end
    end
  rescue SocketError, Errno::ECONNREFUSED, Errno::ETIMEDOUT, Net::OpenTimeout, Net::ReadTimeout => e
    raise Error, "Synthesia API network error: #{e.class}: #{e.message}"
  end

  def download_to_tempfile(uri)
    file = Tempfile.new([ "synthesia-video", File.extname(uri.path).presence || ".mp4" ], binmode: true)

    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 120) do |http|
      request = Net::HTTP::Get.new(uri.request_uri)
      request["Authorization"] = @api_key if ALLOWED_HOSTS.include?(uri.host)

      http.request(request) do |response|
        case response
        when Net::HTTPSuccess
          response.read_body { |chunk| file.write(chunk) }
        else
          file.close!
          raise Error, "Synthesia download error #{response.code}: #{response.body.to_s[0, 200]}"
        end
      end
    end

    file.rewind
    yield file
  ensure
    file.close! if file && !file.closed?
  end

  def build_filename(video_payload, uri)
    title = video_payload["title"].to_s.parameterize
    extension = File.extname(uri.path).presence || ".mp4"
    base = title.presence || "synthesia-video-#{video_payload['id']}"
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
