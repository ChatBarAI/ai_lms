require "ipaddr"
require "net/http"
require "resolv"
require "uri"

class SecureHttpFetcher
  class Error < StandardError; end

  Result = Data.define(:body, :content_type, :uri)

  MAX_REDIRECTS = 5
  OPEN_TIMEOUT = 10
  READ_TIMEOUT = 30

  def initialize(max_redirects: MAX_REDIRECTS, resolver: Resolv.method(:getaddresses))
    @max_redirects = max_redirects
    @resolver = resolver
  end

  def fetch(url, max_bytes:, allowed_content_types:, allowed_origin: nil)
    uri = parse_uri(url)
    fetch_uri(
      uri,
      max_bytes: max_bytes,
      allowed_content_types: allowed_content_types,
      allowed_origin: allowed_origin,
      redirects_left: @max_redirects
    )
  end

  private

  def fetch_uri(uri, max_bytes:, allowed_content_types:, allowed_origin:, redirects_left:)
    validate_allowed_origin!(uri, allowed_origin) if allowed_origin
    addresses = validate_uri!(uri)
    perform_request(uri, addresses.first) do |response|
      case response
      when Net::HTTPSuccess
        content_type = validate_content_type!(response, allowed_content_types)
        Result.new(
          body: read_body!(response, max_bytes),
          content_type: content_type,
          uri: uri
        )
      when Net::HTTPRedirection
        raise Error, "Too many redirects" if redirects_left <= 0

        location = response["Location"].to_s
        raise Error, "Redirect did not include a location" if location.blank?

        fetch_uri(
          URI.join(uri, location),
          max_bytes: max_bytes,
          allowed_content_types: allowed_content_types,
          allowed_origin: allowed_origin,
          redirects_left: redirects_left - 1
        )
      else
        raise Error, "Request failed with HTTP #{response.code}"
      end
    end
  end

  def perform_request(uri, validated_ip)
    http = Net::HTTP.new(uri.host, uri.port)
    http.ipaddr = validated_ip
    http.use_ssl = true
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT

    request = Net::HTTP::Get.new(uri.request_uri)
    request["Accept-Encoding"] = "identity"
    request["User-Agent"] = "ai-lms-web-import/1.0"
    request["Accept"] = "text/html,text/css,image/*;q=0.9,*/*;q=0.1"
    result = nil
    http.request(request) { |response| result = yield response }
    result
  rescue SocketError, SystemCallError, Timeout::Error, Net::OpenTimeout, Net::ReadTimeout => error
    raise Error, "Network error: #{error.class}: #{error.message}"
  end

  def read_body!(response, max_bytes)
    declared_size = Integer(response["Content-Length"], exception: false)
    raise Error, "Response exceeds #{max_bytes} bytes" if declared_size && declared_size > max_bytes

    body = +""
    response.read_body do |chunk|
      raise Error, "Response exceeds #{max_bytes} bytes" if body.bytesize + chunk.bytesize > max_bytes

      body << chunk
    end
    body
  end

  def validate_content_type!(response, allowed)
    content_type = response["Content-Type"].to_s.split(";", 2).first.to_s.strip.downcase
    raise Error, "Response returned an unsupported content type" unless Array(allowed).include?(content_type)

    content_type
  end

  def parse_uri(url)
    URI.parse(url.to_s)
  rescue URI::InvalidURIError => error
    raise Error, "Invalid URL: #{error.message}"
  end

  def validate_uri!(uri)
    raise Error, "URL must use HTTPS" unless uri.scheme == "https"
    raise Error, "URL must include a hostname" if uri.host.blank?
    raise Error, "URL must not include credentials" if uri.userinfo.present?

    addresses = @resolver.call(uri.host).uniq
    raise Error, "Hostname could not be resolved" if addresses.empty?

    parsed_addresses = addresses.map { |address| IPAddr.new(address) }
    if parsed_addresses.any? { |address| blocked_address?(address) }
      raise Error, "Destination resolves to a private or reserved address"
    end

    addresses
  rescue IPAddr::InvalidAddressError, Resolv::ResolvError => error
    raise Error, "Hostname could not be resolved: #{error.message}"
  end

  def validate_allowed_origin!(uri, origin)
    origin = parse_uri(origin) unless origin.is_a?(URI::Generic)
    return if uri.scheme == origin.scheme && uri.host&.casecmp?(origin.host) && uri.port == origin.port

    raise Error, "Subresource redirected outside the page origin"
  end

  def blocked_address?(address)
    SecureRemoteDownloader::BLOCKED_NETWORKS.any? do |network|
      network.ipv4? == address.ipv4? && network.include?(address)
    end
  end
end
