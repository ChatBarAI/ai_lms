# frozen_string_literal: true

# Stripe configuration
Rails.application.configure do
  config.stripe = {
    publishable_key: Rails.application.credentials.stripe&.publishable_key || ENV["STRIPE_PUBLISHABLE_KEY"],
    secret_key: Rails.application.credentials.stripe&.secret_key || ENV["STRIPE_SECRET_KEY"],
    webhook_secret: Rails.application.credentials.stripe&.webhook_secret || ENV["STRIPE_WEBHOOK_SECRET"]
  }
end

# Set Stripe API key
Stripe.api_key = Rails.configuration.stripe[:secret_key]

# Set Stripe API version
Stripe.api_version = "2023-10-16"

# Set app info for Stripe API calls
Stripe.set_app_info("AI LMS", version: "1.0.0")
