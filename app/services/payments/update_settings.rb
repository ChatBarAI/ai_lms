module Payments
  class UpdateSettings
    CREDENTIAL_FIELDS = %w[stripe_secret_key stripe_webhook_secret].freeze

    def call(settings, attributes)
      values = attributes.to_h.stringify_keys.except("stripe_account_id")
      CREDENTIAL_FIELDS.each do |field|
        next unless values.key?(field)
        values[field] = values[field].to_s.strip
        values.delete(field) if values[field].blank?
      end
      # Shared with checkout-attempt creation: switching identity cannot race
      # the first purchase. Failed checks roll back the entire settings change.
      settings.with_lock do
        previous_account = effective(settings, "account_id")
        previous_mode = live?(effective(settings, "secret_key"))
        settings.assign_attributes(values)
        return false unless settings.valid?
        if CREDENTIAL_FIELDS.any? { |field| values.key?(field) }
          key = effective(settings, "secret_key")
          webhook_secret = effective(settings, "webhook_secret")
          if [ key, webhook_secret ].any?(&:blank?)
            return reject(settings, "credentials_required")
          end
          client = StripeClient.new(secret_key: key)
          remote_account = client.request(:get, "/account")
          balance = client.request(:get, "/balance")
          account = remote_account["id"]
          unless account.is_a?(String) && account.match?(/\Aacct_[A-Za-z0-9]+\z/) && balance["livemode"] == live?(key)
            return reject(settings, "connection_mismatch")
          end
          if history_for_other_identity?(account, live?(key))
            return reject(settings, "identity_locked")
          end
          changed_identity = previous_account.present? && (previous_account != account || previous_mode != live?(key))
          if changed_identity && !values.key?("stripe_webhook_secret")
            return reject(settings, "new_webhook_required")
          end
          settings.stripe_account_id = account
          settings.payment_live_ready = false if changed_identity
        end
        settings.save!
        true
      end
    rescue Payments::Error
      reject(settings, "connection_failed")
    rescue ActiveRecord::Encryption::Errors::Base
      reject(settings, "encryption_failed")
    end

    private

    def effective(settings, name)
      settings.public_send("stripe_#{name}").presence || Configuration.fallback_secret(name)
    end

    def live?(key)
      key.to_s.start_with?("sk_live_", "rk_live_")
    end

    def history_for_other_identity?(account, mode)
      [ Purchase, PaymentEvent ].any? do |model|
        model.where.not(account_id: account).or(model.where.not(livemode: mode)).exists?
      end
    end

    def reject(settings, message)
      settings.errors.add(:base, I18n.t("payments.#{message}"))
      false
    end
  end
end
