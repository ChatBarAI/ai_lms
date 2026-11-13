module Entitlements
  class Transition
    def self.call(grant:, action:, source:, reason:, reference:, actor: nil)
      raise ArgumentError, "Reason required" if reason.blank?
      raise CanCan::AccessDenied unless actor&.admin? || (source == "stripe" && grant.source == "stripe")
      status = { "suspend" => "suspended", "revoke" => "revoked", "restore" => "active" }.fetch(action)
      grant.with_lock do
        return grant if grant.status == status
        # Automatic restoration is limited to a dispute suspension; never undo a revocation.
        return grant if source == "stripe" && (grant.status == "revoked" || (action == "restore" && grant.reason != "stripe_dispute"))
        grant.update!(status: status, reason: reason,
          revoked_at: status == "revoked" ? Time.current : nil,
          suspended_at: status == "suspended" ? Time.current : nil)
        grant.entitlement_events.create!(actor: actor, source: source, action: action, reason: reason, correlation_reference: reference)
        grant
      end
    end
  end
end
