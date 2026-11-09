# frozen_string_literal: true

# Kinde SSO — only configured when credentials are present.
#
# Required credentials (bin/rails credentials:edit):
#   kinde:
#     domain:        https://yourapp.kinde.com
#     client_id:     <client ID from Kinde dashboard>
#     client_secret: <client secret from Kinde dashboard>
#     access_token_audience: <API audience configured in Kinde>
#     connection_id_claim: <signed ID-token claim of actual login connection>
# See SECURITY_REVIEW.md for tenant verification and rollout requirements.
#
# Callback URL to register in Kinde dashboard:
#   <APP_HOST>/kinde/callback
#
# Logout redirect URL to register in Kinde dashboard:
#   <APP_HOST>/kinde/logout_callback

kinde_domain        = Rails.application.credentials.dig(:kinde, :domain)
kinde_client_id     = Rails.application.credentials.dig(:kinde, :client_id)
kinde_client_secret = Rails.application.credentials.dig(:kinde, :client_secret)
kinde_host          = ENV["APP_HOST"].presence ||
                      Rails.application.credentials.dig(:kinde, :host).presence ||
                      "http://localhost:3000"

if kinde_domain.present? && kinde_client_id.present? && kinde_client_secret.present?
  KindeSdk.configure do |c|
    c.expected_issuer = kinde_domain
    # API audience configured in Kinde; deliberately no generic audience fallback.
    c.expected_audience = Rails.application.credentials.dig(:kinde, :access_token_audience)
    c.domain        = kinde_domain
    c.client_id     = kinde_client_id
    c.client_secret = kinde_client_secret
    c.callback_url  = "#{kinde_host}/kinde/callback"
    c.logout_url    = "#{kinde_host}/kinde/logout_callback"
    c.logger        = Rails.logger
  end
end
