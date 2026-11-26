require "test_helper"

class OutboundConnectionErrorTest < ActiveSupport::TestCase
  test "connection failures point at outbound access, not a retry" do
    [ SocketError.new("getaddrinfo: Name or service not known"), Errno::ECONNREFUSED.new,
      Errno::EHOSTUNREACH.new, Net::OpenTimeout.new, OpenSSL::SSL::SSLError.new ].each do |error|
      message = OutboundConnectionError.message(error, host: "api.anam.ai", service: "Anam")

      assert_includes message, "this server couldn't connect to api.anam.ai (#{error.class})"
      assert_includes message, "allows outbound HTTPS to api.anam.ai"
      refute_includes message, "Try again shortly"
    end
  end

  test "a slow response is reported as temporary" do
    message = OutboundConnectionError.message(Net::ReadTimeout.new, host: "api.anam.ai", service: "Anam")

    assert_equal "Anam didn't respond in time. Try again shortly", message
  end
end
