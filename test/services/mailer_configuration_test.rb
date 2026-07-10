require "test_helper"

class MailerConfigurationTest < ActiveSupport::TestCase
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
