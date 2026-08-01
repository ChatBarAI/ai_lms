require "test_helper"

class SecureHttpFetcherTest < ActiveSupport::TestCase
  FakeHttp = Struct.new(:ipaddr, :use_ssl, :open_timeout, :read_timeout) do
    def request(_request)
      yield :response
      :net_http_adapter
    end
  end

  test "accepts a public HTTPS URL" do
    fetcher = SecureHttpFetcher.new(resolver: ->(_host) { [ "93.184.216.34" ] })

    assert_equal [ "93.184.216.34" ], fetcher.send(:validate_uri!, URI("https://example.com/page"))
  end

  test "rejects HTTP credentials and private destinations" do
    public_fetcher = SecureHttpFetcher.new(resolver: ->(_host) { [ "93.184.216.34" ] })
    private_fetcher = SecureHttpFetcher.new(resolver: ->(_host) { [ "127.0.0.1" ] })

    assert_raises(SecureHttpFetcher::Error) { public_fetcher.send(:validate_uri!, URI("http://example.com")) }
    assert_raises(SecureHttpFetcher::Error) { public_fetcher.send(:validate_uri!, URI("https://user:pass@example.com")) }
    assert_raises(SecureHttpFetcher::Error) { private_fetcher.send(:validate_uri!, URI("https://internal.example")) }
  end

  test "locks subresources and their redirects to the page origin" do
    fetcher = SecureHttpFetcher.new
    origin = URI("https://example.com/page")

    assert_nil fetcher.send(:validate_allowed_origin!, URI("https://example.com/assets/site.css"), origin)
    assert_raises(SecureHttpFetcher::Error) do
      fetcher.send(:validate_allowed_origin!, URI("https://cdn.example.com/site.css"), origin)
    end
  end

  test "returns the consumer result instead of Net HTTP's streaming adapter" do
    fetcher = SecureHttpFetcher.new
    fake_http = FakeHttp.new

    Net::HTTP.stub(:new, fake_http) do
      result = fetcher.send(:perform_request, URI("https://example.com/page"), "93.184.216.34") do |_response|
        "downloaded body"
      end

      assert_equal "downloaded body", result
    end
  end
end
