# Resolve after migrations/bootstrap, using the same precedence as the app.
# Fail on database errors instead of mistaking them for environment-only config.
SiteSetting.first
MailerConfiguration.apply!
uses_relay = ActionMailer::Base.delivery_method.to_s == "smtp" &&
  ActionMailer::Base.smtp_settings[:address].to_s.downcase == "mail"
puts "LMS_MAIL_MODE=#{uses_relay ? 'local' : 'external'}"
