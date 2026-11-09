# frozen_string_literal: true

# Defense-in-depth for CVE-2026-45363 class issues while kinde_sdk depends on jwt 2.x.
# Also enforce issuer, token-specific audience and required claims.
# Remove only when the SDK enforces these same checks, with regression coverage.
if defined?(KindeSdk)
  module KindeJwtHardening
    ASYMMETRIC_ALGORITHMS = %w[RS256 RS384 RS512 PS256 PS384 PS512 ES256 ES384 ES512 EdDSA].freeze

    def validate_jwt_token(token_hash)
      token_hash.each_with_object({}) do |(type, token), claims|
        next unless %w[access_token id_token].include?(type.to_s)

        audience = type.to_s == "id_token" ? @config.client_id : @config.expected_audience
        claims[type.to_s] = jwt_validation(token, "#{@config.domain}#{@config.jwks_url}",
          @config.expected_issuer, audience).fetch(:payload)
      end
    end

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

      if expected_issuer.to_s.empty? || (Array(expected_audience).empty? || Array(expected_audience).any? { |audience| audience.to_s.empty? })
        raise JWT::DecodeError, "Expected issuer and audience must be configured"
      end
      payload, _header = JWT.decode(jwt_token, nil, true,
        algorithms: allowed_algorithms, jwks: jwks,
        iss: expected_issuer, verify_iss: true,
        aud: expected_audience, verify_aud: true,
        verify_expiration: true, verify_iat: true,
        required_claims: %w[iss aud sub exp iat])
      raise JWT::DecodeError, "Token subject is missing" if payload["sub"].to_s.empty?
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
