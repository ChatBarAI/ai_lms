module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private

    def find_verified_user
      verified_user = env["warden"]&.user
      return verified_user if SsoSessionPolicy.allowed?(verified_user, env["rack.session"] || {})
      reject_unauthorized_connection
    end
  end
end
