# Run after db:prepare in Docker. Seed the form for an unconfigured/local relay;
# preserve explicitly configured external SMTP and credentials.
if ENV["SMTP_ADDRESS"] == "mail"
  setting = SiteSetting.current
  local_host = [ "", "localhost", "127.0.0.1", "::1" ].include?(setting.smtp_address.to_s)
  no_credentials = setting.smtp_username.blank? && setting.smtp_password.blank? &&
    ENV["SMTP_USERNAME"].blank? && ENV["SMTP_PASSWORD"].blank?
  delivery_method = setting.mail_delivery_method.presence || ENV["MAIL_DELIVERY_METHOD"].presence
  if local_host && no_credentials && [ nil, "smtp" ].include?(delivery_method)
    setting.update!(
      mail_delivery_method: "smtp", smtp_address: "mail", smtp_port: 25,
      smtp_domain: ENV["APP_DOMAIN"], smtp_authentication: nil,
      smtp_enable_starttls_auto: false, smtp_ssl: false, smtp_tls: false,
      smtp_openssl_verify_mode: "peer",
      mailer_sender: setting.mailer_sender.presence || ENV["MAILER_SENDER"]
    )
    puts "Email settings: private Docker mail relay (mail:25)."
  else
    puts "Email settings: preserved existing SMTP host/credentials."
  end
end
