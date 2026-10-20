require "test_helper"

class ChatbarTokenVerifierTest < ActiveSupport::TestCase
  test "accepts a token whose layout file exists" do
    requested = nil
    response = Net::HTTPOK.new("1.1", "200", "OK")
    start = ->(host, *_args, **_opts) { requested = host; response }

    Net::HTTP.stub(:start, start) do
      assert ChatbarTokenVerifier.verify!(" tok_123 ")
    end
    assert_equal "configs.chatbar-ai.com", requested
  end

  test "rejects a token ChatBar does not recognise" do
    Net::HTTP.stub(:start, ->(*) { Net::HTTPNotFound.new("1.1", "404", "Not Found") }) do
      error = assert_raises(ChatbarTokenVerifier::Error) { ChatbarTokenVerifier.verify!("unknown") }
      assert_match "was not recognised", error.message
    end
  end

  test "reports upstream failures as unverifiable" do
    Net::HTTP.stub(:start, ->(*) { raise Net::OpenTimeout }) do
      error = assert_raises(ChatbarTokenVerifier::Error) { ChatbarTokenVerifier.verify!("tok_123") }
      assert_match "could not be verified", error.message
    end
  end

  test "rejects malformed tokens without calling ChatBar" do
    Net::HTTP.stub(:start, ->(*) { flunk "should not make a request" }) do
      [ "", "   ", "has space", "../etc", "a?b", "a#b", "a" * 256 ].each do |token|
        assert_raises(ChatbarTokenVerifier::Error) { ChatbarTokenVerifier.verify!(token) }
      end
    end
  end

  test "builds the layout URL on the allowlisted host" do
    uri = ChatbarTokenVerifier.new.send(:build_uri, "/tok_123_layout.json")

    assert_equal "configs.chatbar-ai.com", uri.host
    assert_equal "/tok_123_layout.json", uri.path
  end

  test "uses the CBAI_CONFIG_BASE_URL override for local testing" do
    requested = nil
    start = ->(host, port, *_args, **_opts) { requested = "#{host}:#{port}"; Net::HTTPOK.new("1.1", "200", "OK") }

    with_config_base_url("http://localhost:4000") do
      Net::HTTP.stub(:start, start) do
        assert ChatbarTokenVerifier.verify!("tok_123")
      end
    end
    assert_equal "localhost:4000", requested
  end

  test "refuses a non-allowlisted host in production" do
    with_config_base_url("http://localhost:4000") do
      Rails.stub(:env, ActiveSupport::EnvironmentInquirer.new("production")) do
        Net::HTTP.stub(:start, ->(*) { flunk "should not make a request" }) do
          error = assert_raises(ChatbarTokenVerifier::Error) { ChatbarTokenVerifier.verify!("tok_123") }
          assert_match "non-allowlisted host localhost", error.message
        end
      end
    end
  end

  private

  def with_config_base_url(url)
    previous = ENV["CBAI_CONFIG_BASE_URL"]
    ENV["CBAI_CONFIG_BASE_URL"] = url
    yield
  ensure
    ENV["CBAI_CONFIG_BASE_URL"] = previous
  end
end
