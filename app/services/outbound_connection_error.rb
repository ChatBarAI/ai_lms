# Form-friendly messages for failed calls to outside services, so a server that
# can't reach the service (firewall, DNS, proxy) isn't reported as a temporary
# outage. The deploy check (deploy/check-readiness outbound) tests the same hosts.
module OutboundConnectionError
  # No response at all: DNS failure, connection refused or unreachable,
  # connection timeout, or a TLS failure.
  CONNECT_ERRORS = [ SocketError, SystemCallError, Net::OpenTimeout, OpenSSL::SSL::SSLError ].freeze
  # Connected, but the service didn't answer in time.
  RESPONSE_ERRORS = [ Net::ReadTimeout ].freeze
  ERRORS = (CONNECT_ERRORS + RESPONSE_ERRORS).freeze

  # Returns a lower-case clause, for use after "could not be verified: ".
  def self.message(error, host:, service:)
    if RESPONSE_ERRORS.any? { |klass| error.is_a?(klass) }
      "#{service} didn't respond in time. Try again shortly"
    else
      "this server couldn't connect to #{host} (#{error.class}). " \
        "Check that the server allows outbound HTTPS to #{host}"
    end
  end
end
