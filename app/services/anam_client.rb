require "json"
require "net/http"
require "uri"

class AnamClient
  class Error < StandardError; end

  DEFAULT_BASE_URL = ENV.fetch("ANAM_BASE_URL", "https://api.anam.ai").freeze
  ALLOWED_HOSTS = %w[api.anam.ai].freeze

  def initialize(api_key:, base_url: DEFAULT_BASE_URL)
    @api_key = api_key.to_s.strip
    @base_url = base_url
    raise Error, "Missing Anam API key" if @api_key.empty?
  end

  # Creates a short-lived session token for a stateful persona.
  # Docs: https://anam.ai/docs/javascript-sdk/production
  def session_token_for_persona(persona_id)
    persona_id = persona_id.to_s.strip
    raise Error, "Missing Anam persona id" if persona_id.empty?

    uri = build_uri("/v1/auth/session-token")
    body = post_json(uri, {
      personaConfig: {
        personaId: persona_id
      }
    })

    parsed = JSON.parse(body)
    token = parsed["sessionToken"].to_s.strip
    raise Error, "Anam response did not include sessionToken" if token.empty?

    token
  rescue JSON::ParserError => e
    raise Error, "Invalid JSON from Anam: #{e.message}"
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

  def post_json(uri, body_hash)
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 30) do |http|
      req = Net::HTTP::Post.new(uri.request_uri)
      req["Authorization"] = "Bearer #{@api_key}"
      req["Content-Type"] = "application/json"
      req["Accept"] = "application/json"
      req.body = JSON.generate(body_hash)
      res = http.request(req)

      case res
      when Net::HTTPSuccess
        res.body
      else
        raise Error, "Anam API error #{res.code}: #{res.body.to_s[0, 200]}"
      end
    end
  rescue SocketError, Errno::ECONNREFUSED, Errno::ETIMEDOUT, Net::OpenTimeout, Net::ReadTimeout => e
    raise Error, "Anam API network error: #{e.class}: #{e.message}"
  end
end
