# frozen_string_literal: true

# Kinde SSO — only configured when credentials are present.
#
# Required credentials (bin/rails credentials:edit):
#   kinde:
#     domain:        https://yourapp.kinde.com
#     client_id:     <client ID from Kinde dashboard>
#     client_secret: <client secret from Kinde dashboard>
#
# Callback URL to register in Kinde dashboard:
#   <APP_HOST>/kinde/callback
#
# Logout redirect URL to register in Kinde dashboard:
#   <APP_HOST>/kinde/logout_callback

kinde_domain        = Rails.application.credentials.dig(:kinde, :domain)
kinde_client_id     = Rails.application.credentials.dig(:kinde, :client_id)
kinde_client_secret = Rails.application.credentials.dig(:kinde, :client_secret)

if kinde_domain.present? && kinde_client_id.present? && kinde_client_secret.present?
  KindeSdk.configure do |c|
    c.domain        = kinde_domain
    c.client_id     = kinde_client_id
    c.client_secret = kinde_client_secret
    c.callback_url  = "#{Rails.application.credentials.dig(:kinde, :host) || ENV.fetch("APP_HOST", "http://localhost:3000")}/kinde/callback"
    c.logout_url    = "#{Rails.application.credentials.dig(:kinde, :host) || ENV.fetch("APP_HOST", "http://localhost:3000")}/kinde/logout_callback"
    c.logger        = Rails.logger
  end
end
