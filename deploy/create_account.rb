# Loaded through Rails runner by bin/account, including on older deployments.
require "json"
require "securerandom"

module CreateAccount
  def self.run(email:, name:, role:)
    unless %w[admin instructor student].include?(role)
      abort "Invalid account role."
    end
    if User.where("LOWER(email) = ?", email.downcase).exists?
      abort "An account with that email already exists; no changes made. Choose another email."
    end

    password = SecureRandom.alphanumeric(24)
    user = User.new(email: email, name: name, role: role,
      password: password, password_confirmation: password)
    unless user.save
      abort "Account creation failed: #{user.errors.full_messages.join(', ')}"
    end

    puts "Account created."
    puts "ID: #{user.id}"
    puts "Email: #{user.email}"
    puts "Role: #{user.role}"
    puts "Password: #{password}"
    puts "Sign in at /users/sign_in."
  end
end
