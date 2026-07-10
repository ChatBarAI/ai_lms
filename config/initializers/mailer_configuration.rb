Rails.application.config.after_initialize do
  MailerConfiguration.ensure_fresh!
rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished
  # First-time setup before db:create — environment fallbacks remain in place.
end
