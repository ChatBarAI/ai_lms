# Used by deploy/export and deploy/restore for native Rails installations.
# Run through `bin/rails runner` so the effective production database
# configuration (including config/database_password) is available.

operation, transfer_file = ARGV
abort "Usage: bin/rails runner deploy/database_transfer.rb dump|restore FILE" unless %w[dump restore].include?(operation) && transfer_file

configuration = ActiveRecord::Base.connection_db_config.configuration_hash
database = configuration.fetch(:database).to_s
abort "The production database name is empty" if database.empty?

postgres_environment = {
  "PGHOST" => configuration[:host],
  "PGPORT" => configuration[:port]&.to_s,
  "PGUSER" => configuration[:username],
  "PGPASSWORD" => configuration[:password]
}.compact.transform_values(&:to_s)

command = if operation == "dump"
  [
    "pg_dump",
    "--format=custom",
    "--no-owner",
    "--no-privileges",
    "--file", File.expand_path(transfer_file),
    database
  ]
else
  [
    "pg_restore",
    "--clean",
    "--if-exists",
    "--no-owner",
    "--no-privileges",
    "--exit-on-error",
    "--dbname", database,
    File.expand_path(transfer_file)
  ]
end

exec(postgres_environment, *command)
