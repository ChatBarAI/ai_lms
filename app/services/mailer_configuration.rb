require "uri"
require "shellwords"

class MailerConfiguration
  class << self
    def ensure_fresh!
      stamp = current_stamp
      return if @applied_stamp == stamp

      apply!
      @applied_stamp = stamp
    end

    def apply!
      setting = current_setting
      app_url_options = default_url_options(setting)
      sender = mailer_sender(setting, app_url_options)
      delivery_method = mail_delivery_method(setting)

      configure_default_url_options(app_url_options)
      configure_sender(sender)
      configure_delivery_method(delivery_method, setting, app_url_options)
    end

    private

    def current_stamp
      current_setting&.updated_at&.to_f || "env:#{env_signature}"
    rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished, ActiveRecord::StatementInvalid
      "env:#{env_signature}"
    end

    def current_setting
      return unless site_settings_available?

      SiteSetting.first
    rescue => e
      Rails.logger.warn("[Mailer] Could not read SiteSetting: #{e.message}") if Rails.env.production?
      nil
    end

    def site_settings_available?
      ActiveRecord::Base.connection.data_source_exists?("site_settings")
    rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished
      false
    end

    def default_url_options(setting)
      public_app_url = setting_value(setting, :app_url).presence ||
                       ENV["APP_HOST"].presence ||
                       ENV["CALLBACK_HOST"].presence
      return {} if public_app_url.blank?

      public_app_url = "https://#{public_app_url}" unless public_app_url.match?(%r{\Ahttps?://})
      uri = URI.parse(public_app_url)
      options = {
        host: uri.host,
        protocol: "#{uri.scheme}://"
      }
      options[:port] = uri.port unless [ 80, 443 ].include?(uri.port)
      options
    rescue URI::InvalidURIError
      {}
    end

    def mailer_sender(setting, app_url_options)
      setting_value(setting, :mailer_sender).presence ||
        ENV["MAILER_SENDER"].presence ||
        default_sender(app_url_options)
    end

    def default_sender(app_url_options)
      return if app_url_options[:host].blank?

      "no-reply@#{app_url_options[:host]}"
    end

    def mail_delivery_method(setting)
      setting_value(setting, :mail_delivery_method).presence ||
        ENV["MAIL_DELIVERY_METHOD"].presence ||
        (ENV["SMTP_ADDRESS"].present? ? "smtp" : "sendmail")
    end

    def configure_default_url_options(app_url_options)
      return if app_url_options.blank?

      ActionMailer::Base.default_url_options = app_url_options
    end

    def configure_sender(sender)
      return if sender.blank?

      ActionMailer::Base.default from: sender
      ApplicationMailer.default from: sender if defined?(ApplicationMailer)
      Devise.mailer_sender = sender if defined?(Devise)
    end

    def configure_delivery_method(delivery_method, setting, app_url_options)
      return if Rails.env.test?

      ActionMailer::Base.delivery_method = delivery_method.to_sym

      case delivery_method
      when "smtp"
        ActionMailer::Base.smtp_settings = smtp_settings(setting, app_url_options)
      when "sendmail"
        ActionMailer::Base.sendmail_settings = sendmail_settings(setting)
      end
    end

    def smtp_settings(setting, app_url_options)
      settings = {
        address: setting_value(setting, :smtp_address).presence || ENV.fetch("SMTP_ADDRESS", "localhost"),
        port: (setting_value(setting, :smtp_port).presence || ENV.fetch("SMTP_PORT", "587")).to_i,
        domain: setting_value(setting, :smtp_domain).presence ||
                ENV["SMTP_DOMAIN"].presence ||
                app_url_options[:host],
        enable_starttls_auto: smtp_starttls_enabled?(setting)
      }.compact
      settings[:user_name] = setting_value(setting, :smtp_username).presence || ENV["SMTP_USERNAME"].presence
      settings[:password] = setting_value(setting, :smtp_password).presence || ENV["SMTP_PASSWORD"].presence
      auth = setting_value(setting, :smtp_authentication).presence || ENV["SMTP_AUTHENTICATION"].presence
      verify_mode = setting_value(setting, :smtp_openssl_verify_mode).presence ||
                    ENV["SMTP_OPENSSL_VERIFY_MODE"].presence

      settings[:authentication] = auth.to_sym if auth.present?
      settings[:openssl_verify_mode] = verify_mode if verify_mode.present?
      settings[:ssl] = smtp_boolean_setting(setting, :smtp_ssl, "SMTP_SSL")
      settings[:tls] = smtp_boolean_setting(setting, :smtp_tls, "SMTP_TLS")
      settings[:enable_starttls_auto] = false if settings[:ssl] || settings[:tls]
      settings.compact
    end

    def smtp_starttls_enabled?(setting)
      configured = setting_value(setting, :smtp_enable_starttls_auto)
      return configured unless configured.nil?

      ENV.fetch("SMTP_ENABLE_STARTTLS_AUTO", "true") != "false"
    end

    def smtp_boolean_setting(setting, attribute, env_key)
      configured = setting_value(setting, attribute)
      return configured unless configured.nil?
      return if ENV[env_key].blank?

      ActiveModel::Type::Boolean.new.cast(ENV[env_key])
    end

    def sendmail_settings(setting)
      arguments = setting_value(setting, :sendmail_arguments).presence ||
                  ENV.fetch("SENDMAIL_ARGUMENTS", "-i")

      {
        location: setting_value(setting, :sendmail_location).presence ||
                  ENV.fetch("SENDMAIL_LOCATION", "/usr/sbin/sendmail"),
        arguments: Shellwords.split(arguments)
      }
    end

    def setting_value(setting, attribute)
      return unless setting&.has_attribute?(attribute)

      setting.public_send(attribute)
    end

    def env_signature
      %w[
        APP_HOST CALLBACK_HOST MAILER_SENDER MAIL_DELIVERY_METHOD
        SMTP_ADDRESS SMTP_PORT SMTP_DOMAIN SMTP_USERNAME SMTP_PASSWORD SMTP_AUTHENTICATION
        SMTP_ENABLE_STARTTLS_AUTO SMTP_OPENSSL_VERIFY_MODE SMTP_SSL SMTP_TLS
        SENDMAIL_LOCATION SENDMAIL_ARGUMENTS
      ].map { |key| "#{key}=#{ENV[key]}" }.join("|")
    end
  end
end
