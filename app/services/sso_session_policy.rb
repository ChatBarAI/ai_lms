# Shared by ordinary requests, protected file requests and Cable connections.
module SsoSessionPolicy
  def self.allowed?(user, session)
    return false unless user
    return true unless user.mandatory_sso?

    proof = session[:sso_authentication] || session["sso_authentication"]
    return false unless proof.is_a?(Hash)

    proof["user_id"] == user.id &&
      proof["organization_id"] == user.organization_id &&
      proof["connection_id"].present? &&
      proof["connection_id"] == user.organization.kinde_connection_id &&
      proof["expires_at"].to_i > Time.current.to_i
  end
end
