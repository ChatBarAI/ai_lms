# Run through bin/rails runner. Used by native development restore/pull scripts.
require "securerandom"

operation = ARGV.shift || "--ask"
abort "Usage: bin/rails runner deploy/local_admin.rb [--ask|--create|--check]" unless ARGV.empty? && %w[--ask --create --check].include?(operation)
abort "Local admin setup requires RAILS_ENV=development." unless Rails.env.development?

configuration = ActiveRecord::Base.connection_db_config.configuration_hash
host = (configuration[:host] || ENV["PGHOST"]).to_s
unless %w[PGSERVICE PGHOSTADDR].all? { |key| ENV[key].to_s.empty? } &&
    %i[service hostaddr].all? { |key| configuration[key].to_s.empty? }
  abort "Unset PostgreSQL service/hostaddr overrides for local admin setup."
end
unless host.empty? || (host.start_with?("/") && !host.include?(",")) || %w[localhost 127.0.0.1 ::1].include?(host)
  abort "Local admin setup requires a local database."
end
unless configuration.fetch(:database).to_s.end_with?("_development")
  abort "Local admin setup requires a database name ending in _development."
end
exit if operation == "--check"

email = ENV.fetch("SEED_ADMIN_EMAIL", "admin@example.com").strip.downcase
abort "SEED_ADMIN_EMAIL cannot be blank." if email.empty?

if operation == "--ask"
  print "Create or reset local admin #{email}? [y/N] "
  $stdout.flush
  unless %w[y yes].include?($stdin.gets.to_s.strip.downcase)
    puts "Local admin setup skipped."
    exit
  end
end

provided_password = ENV["SEED_ADMIN_PASSWORD"].to_s
password = provided_password.empty? ? SecureRandom.alphanumeric(20) : provided_password
admin = User.find_or_initialize_by(email: email)
admin.name = "Admin" if admin.name.to_s.strip.empty?
admin.assign_attributes(
  role: :admin, password: password, password_confirmation: password,
  failed_attempts: 0, locked_at: nil, unlock_token: nil,
  reset_password_token: nil, reset_password_sent_at: nil,
  remember_created_at: nil
)
admin.save!
puts "Local admin: #{email}"
puts provided_password.empty? ? "Generated password: #{password}" : "Password: supplied via SEED_ADMIN_PASSWORD"
