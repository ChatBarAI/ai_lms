require "ipaddr"
require "net/http"
require "resolv"
require "tempfile"
require "uri"

class SecureRemoteDownloader
  class Error < StandardError; end

  MAX_BYTES = 100.megabytes
  MAX_REDIRECTS = 5
  OPEN_TIMEOUT = 10
  READ_TIMEOUT = 120
  ALLOWED_CONTENT_TYPES = %w[
    video/mp4
    video/webm
    video/ogg
    application/ogg
    application/octet-stream
  ].freeze

  BLOCKED_NETWORKS = %w[
    0.0.0.0/8
    10.0.0.0/8
    100.64.0.0/10
    127.0.0.0/8
    169.254.0.0/16
    172.16.0.0/12
    192.0.0.0/24
    192.0.2.0/24
    192.168.0.0/16
    192.88.99.0/24
    198.18.0.0/15
    198.51.100.0/24
    203.0.113.0/24
    224.0.0.0/4
    240.0.0.0/4
    ::/128
    ::1/128
    ::ffff:0:0/96
    64:ff9b::/96
    100::/64
    2001::/23
    2001:db8::/32
    2002::/16
    fc00::/7
    fe80::/10
    ff00::/8
  ].map { |network| IPAddr.new(network) }.freeze

  def initialize(max_bytes: MAX_BYTES, max_redirects: MAX_REDIRECTS,
                 allow_private_network: false, allow_http: false,
                 allowed_hosts: nil,
                 resolver: Resolv.method(:getaddresses))
    @max_bytes = max_bytes
    @max_redirects = max_redirects
    @allow_private_network = allow_private_network
    @allow_http = allow_http
    @allowed_hosts = Array(allowed_hosts).map { |host| host.to_s.downcase }.reject(&:blank?).uniq
    @resolver = resolver
  end

  def download(url, tempfile_prefix:, headers_for: ->(_uri) { {} })
    uri = parse_uri(url)
    file = Tempfile.new([ tempfile_prefix, File.extname(uri.path).presence || ".bin" ], binmode: true)

    fetch(uri, file, headers_for: headers_for, redirects_left: @max_redirects)
    file.rewind
    validate_video_signature!(file)
    file.rewind
    yield file
  ensure
    file.close! if file && !file.closed?
  end

  private

  def fetch(uri, file, headers_for:, redirects_left:)
    addresses = validate_uri!(uri)
    perform_request(uri, addresses.first, headers_for.call(uri)) do |response|
      case response
      when Net::HTTPSuccess
        write_response!(response, file)
      when Net::HTTPRedirection
        raise Error, "Too many redirects" if redirects_left <= 0

        location = response["Location"].to_s
        raise Error, "Download redirect did not include a location" if location.blank?

        next_uri = URI.join(uri, location)
        fetch(next_uri, file, headers_for: headers_for, redirects_left: redirects_left - 1)
      else
        raise Error, "Download failed with HTTP #{response.code}"
      end
    end
  end

  def perform_request(uri, validated_ip, headers)
    http = Net::HTTP.new(uri.host, uri.port)
    http.ipaddr = validated_ip
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT

    request = Net::HTTP::Get.new(uri.request_uri)
    headers.each { |name, value| request[name] = value }
    http.request(request) { |response| yield response }
  rescue SocketError, SystemCallError, Timeout::Error, Net::OpenTimeout, Net::ReadTimeout => e
    raise Error, "Download network error: #{e.class}: #{e.message}"
  end

  def write_response!(response, file)
    content_type = response["Content-Type"].to_s.split(";", 2).first.to_s.strip.downcase
    unless ALLOWED_CONTENT_TYPES.include?(content_type)
      raise Error, "Download returned an unsupported content type"
    end

    declared_size = Integer(response["Content-Length"], exception: false)
    if declared_size && declared_size > @max_bytes
      raise Error, "Download exceeds the maximum size of #{@max_bytes} bytes"
    end

    bytes_written = 0
    response.read_body do |chunk|
      bytes_written += chunk.bytesize
      raise Error, "Download exceeds the maximum size of #{@max_bytes} bytes" if bytes_written > @max_bytes

      file.write(chunk)
    end
  end

  def validate_video_signature!(file)
    header = file.read(16).to_s.b
    valid = header.start_with?("\x1A\x45\xDF\xA3".b) ||
            header.start_with?("OggS".b) ||
            (header.bytesize >= 12 && header.byteslice(4, 4) == "ftyp".b)
    raise Error, "Downloaded content is not a supported video file" unless valid
  end

  def parse_uri(url)
    URI.parse(url.to_s)
  rescue URI::InvalidURIError => e
    raise Error, "Invalid download URL: #{e.message}"
  end

  def validate_uri!(uri)
    allowed_schemes = @allow_http ? %w[http https] : %w[https]
    raise Error, "Download URL must use HTTPS" unless allowed_schemes.include?(uri.scheme)
    raise Error, "Download URL must include a hostname" if uri.host.blank?
    raise Error, "Download URL must not include credentials" if uri.userinfo.present?
    if @allowed_hosts.any? && !@allowed_hosts.include?(uri.host.downcase)
      raise Error, "Download hostname is not allowlisted"
    end

    addresses = @resolver.call(uri.host).uniq
    raise Error, "Download hostname could not be resolved" if addresses.empty?

    parsed_addresses = addresses.map { |address| IPAddr.new(address) }
    if !@allow_private_network && parsed_addresses.any? { |address| blocked_address?(address) }
      raise Error, "Download destination resolves to a private or reserved address"
    end

    addresses
  rescue IPAddr::InvalidAddressError, Resolv::ResolvError => e
    raise Error, "Download hostname could not be resolved: #{e.message}"
  end

  def blocked_address?(address)
    BLOCKED_NETWORKS.any? do |network|
      network.ipv4? == address.ipv4? && network.include?(address)
    end
  end
end
