require "test_helper"

class AnamClientTest < ActiveSupport::TestCase
  test "constructor rejects blank api key" do
    assert_raises(AnamClient::Error) { AnamClient.new(api_key: "") }
    assert_raises(AnamClient::Error) { AnamClient.new(api_key: nil) }
    assert_raises(AnamClient::Error) { AnamClient.new(api_key: "   ") }
  end

  test "build_uri accepts the default allowlisted host" do
    client = AnamClient.new(api_key: "key")
    uri = client.send(:build_uri, "/v1/auth/session-token")

    assert_equal "api.anam.ai", uri.host
    assert_equal "/v1/auth/session-token", uri.path
  end

  test "build_uri accepts overridden base_url for local testing" do
    client = AnamClient.new(api_key: "key", base_url: "http://localhost:4567")
    uri = client.send(:build_uri, "/v1/auth/session-token")

    assert_equal "localhost", uri.host
  end

  test "session_token_for_persona parses session token" do
    client = AnamClient.new(api_key: "key")

    client.stub(:post_json, '{"sessionToken":"st_123"}') do
      token = client.session_token_for_persona("persona-1")
      assert_equal "st_123", token
    end
  end

  test "session_token_for_persona rejects blank persona id" do
    client = AnamClient.new(api_key: "key")

    assert_raises(AnamClient::Error) { client.session_token_for_persona(nil) }
    assert_raises(AnamClient::Error) { client.session_token_for_persona("  ") }
  end

  test "verify_persona! accepts a readable persona" do
    Net::HTTP.stub(:start, ->(*) { Net::HTTPOK.new("1.1", "200", "OK") }) do
      assert AnamClient.new(api_key: "key").verify_persona!("persona-1")
    end
  end

  test "verify_persona! distinguishes a rejected key from a missing persona" do
    client = AnamClient.new(api_key: "key")

    Net::HTTP.stub(:start, ->(*) { Net::HTTPUnauthorized.new("1.1", "401", "Unauthorized") }) do
      assert_raises(AnamClient::InvalidApiKey) { client.verify_persona!("persona-1") }
    end
    Net::HTTP.stub(:start, ->(*) { Net::HTTPNotFound.new("1.1", "404", "Not Found") }) do
      assert_raises(AnamClient::InvalidPersona) { client.verify_persona!("persona-1") }
    end
  end
end
