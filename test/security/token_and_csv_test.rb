# Runs without Rails/PostgreSQL: bundle exec ruby test/security/token_and_csv_test.rb
require "minitest/autorun"
require "jwt"
require "openssl"
require "logger"
require_relative "../../app/services/spreadsheet_safe"

unless defined?(Rails)
  module Rails
    def self.logger
      @logger ||= Logger.new(File::NULL)
    end
  end
end
module KindeSdk; end unless defined?(KindeSdk)
require_relative "../../config/initializers/kinde_jwt_hardening" unless defined?(KindeJwtHardening)

class TokenAndCsvTest < Minitest::Test
  def setup
    @key = OpenSSL::PKey::RSA.generate(2048)
    @jwk = JWT::JWK.new(@key, use: "sig", alg: "RS256", kid: "test-key")
    @jwks = { keys: [ @jwk.export ] }
    @claims = { "iss" => "https://issuer.example", "aud" => "application", "sub" => "user",
                "iat" => Time.now.to_i, "exp" => Time.now.to_i + 300 }
    @verifier = Object.new.extend(KindeJwtHardening)
  end

  def validate(claims = @claims, key: @key, algorithm: "RS256")
    token = JWT.encode(claims, key, algorithm, kid: "test-key")
    @verifier.send(:validate_token, token, @jwks, "https://issuer.example", "application")
  end

  def test_accepts_valid_signature_and_claims
    assert validate.fetch(:valid)
  end

  def test_rejects_wrong_issuer_audience_expiration_and_missing_claims
    [ { "iss" => "other" }, { "aud" => "other" }, { "exp" => Time.now.to_i - 1 },
     { "iat" => Time.now.to_i + 300 } ].each do |invalid|
      assert_raises(JWT::DecodeError) { validate(@claims.merge(invalid)) }
    end
    %w[iss aud sub exp iat].each do |claim|
      assert_raises(JWT::DecodeError) { validate(@claims.reject { |key, _| key == claim }) }
    end
  end

  def test_rejects_invalid_signatures_and_symmetric_algorithms
    assert_raises(JWT::DecodeError) { validate(key: OpenSSL::PKey::RSA.generate(2048)) }
    assert_raises(JWT::DecodeError) { validate(key: "untrusted-secret", algorithm: "HS256") }
  end

  def test_formula_cells_are_text_and_numbers_remain_numeric
    [ "=1+1", "+1", "-1", "@SUM(A1)", "  =1", "\ttext", "\rtext", "\ntext" ].each do |value|
      assert_equal "'#{value}", SpreadsheetSafe.cell(value)
    end
    assert_equal "Ordinary title", SpreadsheetSafe.cell("Ordinary title")
    assert_equal(-2, SpreadsheetSafe.cell(-2))
    assert_nil SpreadsheetSafe.cell(nil)
  end
end
