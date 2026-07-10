require "active_support/core_ext/integer/time"
require "uri"
require "shellwords"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot. This eager loads most of Rails and
  # your application in memory, allowing both threaded web servers
  # and those relying on copy on write to perform better.
  # Rake tasks automatically ignore this option for performance.
  config.eager_load = true

  # Full error reports are disabled and caching is turned on.
  config.consider_all_requests_local = false
  config.action_controller.perform_caching = true

  # Ensures that a master key has been made available in ENV["RAILS_MASTER_KEY"], config/master.key, or an environment
  # key such as config/credentials/production.key. This key is used to decrypt credentials (and other encrypted files).
  # config.require_master_key = true

  # Disable serving static files from `public/`, relying on NGINX/Apache to do so instead.
  # config.public_file_server.enabled = false

  # Compress CSS using a preprocessor.
  # config.assets.css_compressor = :sass

  # Do not fall back to assets pipeline if a precompiled asset is missed.
  config.assets.compile = false

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Specifies the header that your server uses for sending files.
  # config.action_dispatch.x_sendfile_header = "X-Sendfile" # for Apache
  # config.action_dispatch.x_sendfile_header = "X-Accel-Redirect" # for NGINX

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Mount Action Cable outside main process or domain.
  # config.action_cable.mount_path = nil
  # config.action_cable.url = "wss://example.com/cable"
  # config.action_cable.allowed_request_origins = [ "http://example.com", /http:\/\/example.*/ ]

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  # Can be used together with config.force_ssl for Strict-Transport-Security and secure cookies.
  # config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Skip http-to-https redirect for the default health check endpoint.
  # config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT by default
  config.logger = ActiveSupport::Logger.new(STDOUT)
    .tap  { |logger| logger.formatter = ::Logger::Formatter.new }
    .then { |logger| ActiveSupport::TaggedLogging.new(logger) }

  # Prepend all log lines with the following tags.
  config.log_tags = [ :request_id ]

  # "info" includes generic and useful information about system operation, but avoids logging too much
  # information to avoid inadvertent exposure of personally identifiable information (PII). If you
  # want to log everything, set the level to "debug".
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Use a different cache store in production.
  # config.cache_store = :mem_cache_store

  # Use a real queuing backend for Active Job (and separate queues per environment).
  # config.active_job.queue_adapter = :resque
  # config.active_job.queue_name_prefix = "ai_lms_production"

  # Disable caching for Action Mailer templates even if Action Controller
  # caching is enabled.
  config.action_mailer.perform_caching = false

  # Devise mailers generate absolute URLs, such as password reset links.
  # bin/setup writes APP_HOST into generated production services when
  # --app-url is provided; CALLBACK_HOST is accepted for older deploy notes.
  public_app_url = ENV["APP_HOST"].presence || ENV["CALLBACK_HOST"].presence
  if public_app_url.present?
    unless public_app_url.match?(%r{\Ahttps?://})
      public_app_url = "https://#{public_app_url}"
    end
    uri = URI.parse(public_app_url)
    default_url_options = {
      host: uri.host,
      protocol: "#{uri.scheme}://"
    }
    default_url_options[:port] = uri.port unless [ 80, 443 ].include?(uri.port)
    config.action_mailer.default_url_options = default_url_options
  end

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  mailer_sender = ENV["MAILER_SENDER"].presence
  if mailer_sender.blank? && config.action_mailer.default_url_options&.key?(:host)
    mailer_sender = "no-reply@#{config.action_mailer.default_url_options[:host]}"
  end
  if mailer_sender.present?
    config.action_mailer.default_options = { from: mailer_sender }
  end

  mail_delivery_method = ENV["MAIL_DELIVERY_METHOD"].presence ||
                         (ENV["SMTP_ADDRESS"].present? ? "smtp" : "sendmail")
  config.action_mailer.delivery_method = mail_delivery_method.to_sym

  if mail_delivery_method == "smtp"
    smtp_settings = {
      address: ENV.fetch("SMTP_ADDRESS", "localhost"),
      port: ENV.fetch("SMTP_PORT", "587").to_i,
      domain: ENV["SMTP_DOMAIN"].presence ||
              config.action_mailer.default_url_options&.fetch(:host, nil),
      enable_starttls_auto: ENV.fetch("SMTP_ENABLE_STARTTLS_AUTO", "true") != "false"
    }.compact

    smtp_settings[:user_name] = ENV["SMTP_USERNAME"] if ENV["SMTP_USERNAME"].present?
    smtp_settings[:password] = ENV["SMTP_PASSWORD"] if ENV["SMTP_PASSWORD"].present?
    if ENV["SMTP_AUTHENTICATION"].present?
      smtp_settings[:authentication] = ENV["SMTP_AUTHENTICATION"].to_sym
    end
    if ENV["SMTP_OPENSSL_VERIFY_MODE"].present?
      smtp_settings[:openssl_verify_mode] = ENV["SMTP_OPENSSL_VERIFY_MODE"]
    end
    smtp_settings[:ssl] = ActiveModel::Type::Boolean.new.cast(ENV["SMTP_SSL"]) if ENV["SMTP_SSL"].present?
    smtp_settings[:tls] = ActiveModel::Type::Boolean.new.cast(ENV["SMTP_TLS"]) if ENV["SMTP_TLS"].present?
    smtp_settings[:enable_starttls_auto] = false if smtp_settings[:ssl] || smtp_settings[:tls]
    config.action_mailer.smtp_settings = smtp_settings
  elsif mail_delivery_method == "sendmail"
    config.action_mailer.sendmail_settings = {
      location: ENV.fetch("SENDMAIL_LOCATION", "/usr/sbin/sendmail"),
      arguments: Shellwords.split(ENV.fetch("SENDMAIL_ARGUMENTS", "-i"))
    }
  end

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Enable DNS rebinding protection and other `Host` header attacks.
  # config.hosts = [
  #   "example.com",     # Allow requests from example.com
  #   /.*\.example\.com/ # Allow requests from subdomains like `www.example.com`
  # ]
  # Skip DNS rebinding protection for the default health check endpoint.
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
