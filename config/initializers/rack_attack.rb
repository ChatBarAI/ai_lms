require "digest"

class Rack::Attack
  REDIS_NAMESPACE = "ai_lms:rack_attack".freeze
  THROTTLE_LIMITS = {
    "requests/ip" => { limit: 300, period: 5.minutes },
    "password-login/ip" => { limit: 20, period: 5.minutes },
    "password-login/email" => { limit: 8, period: 5.minutes },
    "password-reset/ip" => { limit: 10, period: 15.minutes },
    "password-reset/email" => { limit: 3, period: 30.minutes },
    "kinde-entry/ip" => { limit: 30, period: 5.minutes },
    "kinde-callback/ip" => { limit: 15, period: 5.minutes },
    "sso-check/ip" => { limit: 30, period: 5.minutes },
    "lesson-api/ip" => { limit: 60, period: 5.minutes },
    "lesson-api/token" => { limit: 30, period: 5.minutes },
    "certificate-verification/ip" => { limit: 60, period: 5.minutes },
    "certificate-verification/token" => { limit: 30, period: 5.minutes },
    "question-callback/ip" => { limit: 60, period: 5.minutes },
    "question-callback/token" => { limit: 15, period: 5.minutes },
    "expensive-actions/user" => { limit: 10, period: 15.minutes },
    "expensive-actions/ip" => { limit: 20, period: 15.minutes }
  }.transform_values(&:freeze).freeze

  def self.redis_url
    SiteSetting.first&.redis_url.presence || ENV["REDIS_URL"].presence || "redis://localhost:6379/0"
  rescue StandardError => e
    Rails.logger.warn("[Rack::Attack] Could not read redis_url from SiteSetting: #{e.message}")
    ENV["REDIS_URL"].presence || "redis://localhost:6379/0"
  end
  private_class_method :redis_url

  # Rack::Attack is automatically Rails middleware, but has no effect without
  # rules. Production counters must be shared by every web process.
  self.cache.store = if Rails.env.production?
    ActiveSupport::Cache::RedisCacheStore.new(url: redis_url, namespace: REDIS_NAMESPACE)
  else
    Rails.cache
  end

  def self.normalized_email(request)
    request.params.dig("user", "email").to_s.strip.downcase.presence
  rescue Rack::QueryParser::ParameterTypeError, Rack::QueryParser::InvalidParameterError
    nil
  end

  def self.token_digest(token)
    value = token.to_s
    Digest::SHA256.hexdigest(value) if value.present?
  end

  def self.signed_in_user_id(request)
    request.env.dig("rack.session", "warden.user.user.key", 0, 0)&.to_s
  end

  throttle("requests/ip", **THROTTLE_LIMITS.fetch("requests/ip")) { |request| request.ip }

  throttle("password-login/ip", **THROTTLE_LIMITS.fetch("password-login/ip")) do |request|
    request.ip if request.post? && request.path == "/users/sign_in"
  end
  throttle("password-login/email", **THROTTLE_LIMITS.fetch("password-login/email")) do |request|
    normalized_email(request) if request.post? && request.path == "/users/sign_in"
  end
  throttle("password-reset/ip", **THROTTLE_LIMITS.fetch("password-reset/ip")) do |request|
    request.ip if request.post? && request.path == "/users/password"
  end
  throttle("password-reset/email", **THROTTLE_LIMITS.fetch("password-reset/email")) do |request|
    normalized_email(request) if request.post? && request.path == "/users/password"
  end

  throttle("kinde-entry/ip", **THROTTLE_LIMITS.fetch("kinde-entry/ip")) do |request|
    request.ip if request.get? && (request.path == "/kinde/login" || request.path.start_with?("/auth/org/"))
  end
  throttle("kinde-callback/ip", **THROTTLE_LIMITS.fetch("kinde-callback/ip")) do |request|
    request.ip if request.get? && request.path == "/kinde/callback"
  end
  throttle("sso-check/ip", **THROTTLE_LIMITS.fetch("sso-check/ip")) do |request|
    request.ip if request.get? && request.path == "/auth/sso_check"
  end

  lesson_api_path = %r{\A/api/lessons/([^/]+)\z}
  throttle("lesson-api/ip", **THROTTLE_LIMITS.fetch("lesson-api/ip")) do |request|
    request.ip if request.get? && request.path.match?(lesson_api_path)
  end
  throttle("lesson-api/token", **THROTTLE_LIMITS.fetch("lesson-api/token")) do |request|
    match = request.path.match(lesson_api_path)
    token_digest(match[1]) if request.get? && match
  end

  certificate_path = %r{\A/certificates/([^/]+)\z}
  throttle("certificate-verification/ip", **THROTTLE_LIMITS.fetch("certificate-verification/ip")) do |request|
    request.ip if request.get? && request.path.match?(certificate_path)
  end
  throttle("certificate-verification/token", **THROTTLE_LIMITS.fetch("certificate-verification/token")) do |request|
    match = request.path.match(certificate_path)
    token_digest(match[1]) if request.get? && match
  end

  callback_path = %r{\A/api/question_generation_tasks/([^/]+)/callback\z}
  callback_methods = %w[POST PUT PATCH].freeze
  throttle("question-callback/ip", **THROTTLE_LIMITS.fetch("question-callback/ip")) do |request|
    request.ip if callback_methods.include?(request.request_method) && request.path.match?(callback_path)
  end
  throttle("question-callback/token", **THROTTLE_LIMITS.fetch("question-callback/token")) do |request|
    match = request.path.match(callback_path)
    token_digest(match[1]) if callback_methods.include?(request.request_method) && match
  end

  expensive_path = %r{\A/courses/[^/]+/lessons/[^/]+/(?:video/import(?:_synthesia|_heygen)?|question_generation_tasks)\z}
  throttle("expensive-actions/user", **THROTTLE_LIMITS.fetch("expensive-actions/user")) do |request|
    signed_in_user_id(request) if request.post? && request.path.match?(expensive_path)
  end
  throttle("expensive-actions/ip", **THROTTLE_LIMITS.fetch("expensive-actions/ip")) do |request|
    request.ip if request.post? && request.path.match?(expensive_path)
  end

  self.throttled_responder = lambda do |request|
    match_data = request.env["rack.attack.match_data"] || {}
    retry_after = match_data[:period].to_i
    retry_after = 60 if retry_after <= 0
    [ 429,
      { "Content-Type" => "text/plain; charset=utf-8", "Retry-After" => retry_after.to_s, "Cache-Control" => "no-store" },
      [ "Rate limit exceeded. Try again later.\n" ] ]
  end
end
