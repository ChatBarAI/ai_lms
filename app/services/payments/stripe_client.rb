require "net/http"
require "json"

module Payments
  # Small adapter; secrets and provider response bodies never enter error messages.
  class StripeClient
    API_VERSION = "2026-10-28.endive".freeze

    def initialize(secret_key: nil)
      @secret_key = secret_key
    end

    def request(method, path, params = {}, idempotency_key: nil)
      raise Error, "Invalid Stripe resource" unless path.match?(%r{\A/[a-zA-Z0-9_/]+\z})
      uri = URI("https://api.stripe.com/v1#{path}")
      encoded = URI.encode_www_form(flatten(params))
      uri.query = encoded if method == :get && encoded.present?
      request = (method == :get ? Net::HTTP::Get : Net::HTTP::Post).new(uri)
      request.basic_auth(@secret_key || Configuration.secret("secret_key"), "")
      request["Stripe-Version"] = API_VERSION
      request["Idempotency-Key"] = idempotency_key if idempotency_key
      request.set_form_data({}) if method == :post
      request.body = encoded if method == :post
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 20) { |http| http.request(request) }
      raise Error, "Stripe HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
      JSON.parse(response.body)
    rescue JSON::ParserError, IOError, SystemCallError, Timeout::Error, SocketError, OpenSSL::SSL::SSLError, Net::HTTPBadResponse => e
      raise Error, "Stripe unavailable (#{e.class.name})"
    end

    def verify_account!(purchase = nil)
      account = request(:get, "/account")
      expected = purchase ? purchase.account_id : Configuration.secret("account_id")
      raise Error, "Stripe account mismatch" unless account["id"] == expected
      raise Error, "Stripe environment mismatch" if purchase && purchase.livemode != Configuration.livemode?
    end

    private

    def flatten(value, prefix = nil)
      case value
      when Hash
        value.flat_map { |key, item| flatten(item, prefix ? "#{prefix}[#{key}]" : key.to_s) }
      when Array
        value.each_with_index.flat_map { |item, i| flatten(item, "#{prefix}[#{i}]") }
      else
        [ [ prefix, value.to_s ] ]
      end
    end
  end
end
