# Never carry Kinde proof into password, remember-me, or other sign-in sessions.
# The Kinde callback installs fresh proof only after sign_in completes.
Warden::Manager.after_set_user except: :fetch do |_user, auth, _options|
  auth.request.session.delete(:sso_authentication)
end
Warden::Manager.before_logout do |_user, auth, _options|
  auth.request.session.delete(:sso_authentication)
end
