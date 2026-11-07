# Subprocess-only fixture; launched by test/deploy/configure_mail_test.rb.
# Standalone: ruby test/deploy/configure_mail_test.rb; fake settings, no Rails/DB.
require "ostruct"

class Object
  def blank?
    nil? || (respond_to?(:empty?) && empty?)
  end

  def presence
    self unless blank?
  end
end

class FakeMailSetting < OpenStruct
  def update!(attributes)
    self.saved = attributes
    attributes.each { |key, value| self[key] = value }
  end
end

class SiteSetting
  class << self
    attr_accessor :current
  end
end

keys = %w[SMTP_ADDRESS SMTP_USERNAME SMTP_PASSWORD APP_DOMAIN MAILER_SENDER MAIL_DELIVERY_METHOD]
previous = keys.to_h { |key| [ key, ENV[key] ] }
begin
  keys.each { |key| ENV.delete(key) }
  ENV["SMTP_ADDRESS"] = "mail"
  ENV["APP_DOMAIN"] = "academy.example.com"
  ENV["MAILER_SENDER"] = "no-reply@academy.example.com"
  script = File.expand_path("../../../deploy/configure_mail.rb", __dir__)
  [ nil, "localhost", "127.0.0.1" ].each do |host|
    SiteSetting.current = FakeMailSetting.new(smtp_address: host)
    load script
    setting = SiteSetting.current
    raise "Seed private relay" unless setting.smtp_address == "mail" && setting.smtp_port == 25 && setting.smtp_enable_starttls_auto == false
    raise "Seed sender" unless setting.mailer_sender == ENV["MAILER_SENDER"]
    setting.saved = nil
    load script
    raise "Do not overwrite an existing mail setup" if setting.saved
  end
  [ { smtp_address: "smtp.example.com" }, { smtp_address: "localhost", smtp_password: "secret" },
    { mail_delivery_method: "sendmail" } ].each do |attributes|
    SiteSetting.current = FakeMailSetting.new(attributes)
    load script
    raise "Preserve configured providers/credentials" if SiteSetting.current.saved
  end
  ENV["SMTP_ADDRESS"] = "smtp.example.com"
  SiteSetting.current = FakeMailSetting.new
  load script
  raise "Preserve environment provider" if SiteSetting.current.saved
ensure
  previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
end
puts "Mail settings bootstrap checks passed."
