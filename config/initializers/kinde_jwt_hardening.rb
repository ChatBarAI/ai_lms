# frozen_string_literal: true

# Defense-in-depth for CVE-2026-45363 class issues while kinde_sdk depends on jwt 2.x.
# We constrain Kinde token verification to asymmetric algorithms only.
# Remove this patch after upgrading to a kinde_sdk release that supports jwt 3.2.0+.
if defined?(KindeSdk)
  module KindeJwtHardening
    ASYMMETRIC_ALGORITHMS = %w[RS256 RS384 RS512 PS256 PS384 PS512 ES256 ES384 ES512 EdDSA].freeze

    private

    def validate_token(jwt_token, jwks_hash, expected_issuer, expected_audience)
      decoded_token = JWT.decode(jwt_token, nil, false)
      header = decoded_token[1] || {}
      raise JWT::DecodeError, "Token is missing kid header" if header["kid"].to_s.empty?

      jwks = JWT::JWK::Set.new(jwks_hash)
      jwks.filter! { |key| key[:use] == "sig" }
      algorithms = jwks.map { |key| key[:alg] }.compact.uniq
      allowed_algorithms = algorithms & ASYMMETRIC_ALGORITHMS

      raise JWT::DecodeError, "No allowed asymmetric signing algorithms in JWKS" if allowed_algorithms.empty?

      payload, _header = JWT.decode(jwt_token, nil, true, algorithms: allowed_algorithms, jwks: jwks)
      { valid: true, payload: payload }
    rescue JWT::DecodeError => e
      Rails.logger.error("Token validation failed: #{e.message}")
      raise JWT::DecodeError, "Token validation failed: #{e.message}"
    rescue StandardError => e
      Rails.logger.error("Unexpected error: #{e.message}")
      raise StandardError, "Unexpected error: #{e.message}"
    end
  end

  KindeSdk.singleton_class.prepend(KindeJwtHardening)
end
