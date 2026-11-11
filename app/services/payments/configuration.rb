module Payments
  class Configuration
    def self.secret(name)
      raise ArgumentError, "Unknown Stripe setting" unless %w[secret_key webhook_secret account_id].include?(name.to_s)
      # No process-level memoization: web requests and jobs see committed changes.
      settings = SiteSetting.uncached { SiteSetting.first }
      stored = settings&.has_attribute?("stripe_#{name}") && settings.public_send("stripe_#{name}")
      stored.presence || fallback_secret(name)
    end

    def self.fallback_secret(name)
      ENV["STRIPE_#{name.upcase}"].presence || Rails.application.credentials.dig(:stripe, name.to_sym)
    end

    def self.livemode?
      secret("secret_key").to_s.start_with?("sk_live_", "rk_live_")
    end

    def self.base_url
      value = SiteSetting.current.app_url.to_s.delete_suffix("/")
      uri = URI.parse(value)
      local_test_url = Rails.env.development? && uri.scheme == "http" &&
        %w[localhost 127.0.0.1 ::1].include?(uri.hostname) &&
        secret("secret_key").to_s.start_with?("sk_test_", "rk_test_")
      valid_origin = uri.host && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil? && [ "", "/" ].include?(uri.path)
      raise Error, "Configure an HTTPS application URL" unless valid_origin && (uri.scheme == "https" || local_test_url)
      value
    rescue URI::InvalidURIError
      raise Error, "Invalid application URL"
    end

    def self.problems
      settings = SiteSetting.current
      errors = []
      %w[secret_key webhook_secret account_id].each { |key| errors << "STRIPE_#{key.upcase}" if secret(key).blank? }
      errors << "tax configuration" unless %w[automatic exempt].include?(settings.payment_tax_mode)
      errors << "currency" unless Currency::RULES.key?(settings.payment_currency)
      errors << "course repricing" if Course.where(access_policy: "entitlement_required").where.not(price_currency: settings.payment_currency).exists?
      errors << "seller, terms and support" if [ settings.payment_seller_name, settings.payment_terms_url, settings.payment_support_email ].any?(&:blank?)
      errors << "live readiness confirmation" if livemode? && !settings.payment_live_ready?
      errors << "recovery scheduler" if livemode? && (settings.payment_recovery_at.nil? || settings.payment_recovery_at < 10.minutes.ago)
      begin
        base_url
      rescue Error => e
        errors << e.message
      end
      errors
    end

    def self.checkout_ready?
      SiteSetting.current.payments_enabled? && problems.empty?
    end
  end
end
