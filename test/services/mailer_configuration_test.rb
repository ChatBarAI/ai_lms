require "test_helper"

class MailerConfigurationTest < ActiveSupport::TestCase
  test "sender uses the site brand while retaining the configured email address" do
    setting = SiteSetting.new(brand_name: "Acme, Learning", mailer_sender: "no-reply@example.com")
    sender = MailerConfiguration.send(:mailer_sender, setting, {})
    address = Mail::Address.new(sender)

    assert_equal "Acme, Learning", address.display_name
    assert_equal "no-reply@example.com", address.address
  end

  test "sender falls back to the default brand and strips brand line breaks" do
    setting = SiteSetting.new(brand_name: nil, mailer_sender: "no-reply@example.com")
    sender = MailerConfiguration.send(:mailer_sender, setting, {})
    assert_equal "ChatBar AI Learn", Mail::Address.new(sender).display_name

    setting.brand_name = "Acme\r\nAcademy"
    sender = MailerConfiguration.send(:mailer_sender, setting, {})
    assert_equal "Acme Academy", Mail::Address.new(sender).display_name
    assert_no_match(/[\r\n]/, sender)
  end

  test "Docker mail defaults apply only to the private relay" do
    keys = %w[SMTP_ADDRESS SMTP_PORT SMTP_ENABLE_STARTTLS_AUTO]
    previous = keys.to_h { |key| [ key, ENV[key] ] }
    keys.each { |key| ENV.delete(key) }
    ENV["SMTP_ADDRESS"] = "mail"
    setting = SiteSetting.new
    settings = MailerConfiguration.send(:smtp_settings, setting, host: "academy.example.com")
    assert_equal 25, settings[:port]
    assert_equal false, settings[:enable_starttls_auto]

    setting.smtp_address = "smtp.example.com"
    settings = MailerConfiguration.send(:smtp_settings, setting, host: "academy.example.com")
    assert_equal 587, settings[:port]
    assert_equal true, settings[:enable_starttls_auto]
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  test "SMTP SSL and TLS settings enable implicit TLS and disable STARTTLS" do
    setting = SiteSetting.current
    setting.update!(
      smtp_address: "smtp.sendgrid.net",
      smtp_port: 465,
      smtp_enable_starttls_auto: true,
      smtp_ssl: true,
      smtp_tls: true
    )

    settings = MailerConfiguration.send(:smtp_settings, setting, host: "academy.example.com")

    assert_equal true, settings[:ssl]
    assert_equal true, settings[:tls]
    assert_equal false, settings[:enable_starttls_auto]
  end

  test "SMTP without implicit TLS preserves STARTTLS" do
    setting = SiteSetting.current
    setting.update!(smtp_enable_starttls_auto: true, smtp_ssl: false, smtp_tls: false)

    settings = MailerConfiguration.send(:smtp_settings, setting, host: "academy.example.com")

    assert_equal true, settings[:enable_starttls_auto]
    assert_equal false, settings[:ssl]
    assert_equal false, settings[:tls]
  end
end
