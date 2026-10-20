require "net/http"
require "uri"

# Checks that a ChatBar instance token resolves to a published ChatBar
# configuration, using the same public layout file the embed script loads.
class ChatbarTokenVerifier
  class Error < StandardError; end

  DEFAULT_BASE_URL = ENV.fetch("CBAI_CONFIG_BASE_URL", "https://configs.chatbar-ai.com").freeze
  ALLOWED_HOSTS = %w[configs.chatbar-ai.com].freeze
  # Real tokens are opaque; only reject values that cannot be a single path segment.
  TOKEN_FORMAT = %r{\A[^\s/?#%\\]{1,255}\z}

  def self.verify!(token)
    new.verify!(token)
  end

  def initialize(base_url: DEFAULT_BASE_URL)
    @base_url = base_url
  end

  # Returns true, or raises Error with a message suitable for a form error.
  def verify!(token)
    token = token.to_s.strip
    raise Error, "is not a valid ChatBar instance token" unless TOKEN_FORMAT.match?(token)

    uri = build_uri("/#{ERB::Util.url_encode(token)}_layout.json")
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 10) do |http|
      req = Net::HTTP::Get.new(uri.request_uri)
      req["Accept"] = "application/json"
      http.request(req)
    end

    case res
    when Net::HTTPSuccess
      true
    when Net::HTTPNotFound, Net::HTTPForbidden
      raise Error, "was not recognised by ChatBar AI. Check the token and try again"
    else
      raise Error, "could not be verified with ChatBar AI (HTTP #{res.code}). Try again shortly"
    end
  rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError => e
    raise Error, "could not be verified with ChatBar AI (#{e.class}). Try again shortly"
  end

  private

  def build_uri(path)
    uri = URI.parse(@base_url + path)
    unless %w[http https].include?(uri.scheme) &&
           (ALLOWED_HOSTS.include?(uri.host) || @base_url != DEFAULT_BASE_URL)
      raise Error, "could not be verified: refusing to call non-allowlisted host #{uri.host}"
    end
    uri
  end
end
