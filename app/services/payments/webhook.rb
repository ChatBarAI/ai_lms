require "openssl"
module Payments
  class Webhook
    TYPES = %w[checkout.session.completed checkout.session.expired charge.refunded refund.created refund.updated refund.failed charge.dispute.created charge.dispute.updated charge.dispute.closed charge.dispute.funds_reinstated charge.dispute.funds_withdrawn].freeze

    def self.receive(body, signature)
      secret = Configuration.secret("webhook_secret")
      raise Error, "Webhook not configured" if secret.blank?
      parts = signature.to_s.split(",").map { |part| part.split("=", 2) }
      timestamp = parts.find { |key, _| key == "t" }&.last.to_s
      raise Error, "Invalid signature timestamp" unless timestamp.match?(/\A\d+\z/) && (Time.now.to_i - timestamp.to_i).abs <= 300
      expected = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{body}")
      verified = parts.any? { |key, value| key == "v1" && value && ActiveSupport::SecurityUtils.secure_compare(expected, value) }
      raise Error, "Invalid signature" unless verified
      event = JSON.parse(body)
      raise Error, "Environment mismatch" unless event["livemode"] == Configuration.livemode?
      account = event["account"] || Configuration.secret("account_id")
      raise Error, "Account mismatch" unless account.present? && account == Configuration.secret("account_id")
      return unless TYPES.include?(event["type"])
      # Keep identifiers only; do not retain billing addresses, cards or full payloads.
      PaymentEvent.create_or_find_by!(account_id: account, livemode: event.fetch("livemode"), provider_event_id: event.fetch("id")) do |row|
        row.event_type = event.fetch("type")
        row.object_id = event.fetch("data").fetch("object").fetch("id")
      end
    rescue JSON::ParserError, KeyError
      raise Error, "Invalid event"
    end
  end
end
