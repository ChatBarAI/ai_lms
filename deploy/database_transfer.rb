# Used by deploy/export and deploy/restore for native Rails installations.
# Run through `bin/rails runner` so the selected Rails environment's database
# configuration (including config/database_password) is available.

operation, transfer_file = ARGV
abort "Usage: bin/rails runner deploy/database_transfer.rb dump|restore FILE" unless %w[dump restore].include?(operation) && transfer_file

database_config = ActiveRecord::Base.connection_db_config
configuration = database_config.configuration_hash
database = configuration.fetch(:database).to_s
abort "The database name is empty" if database.empty?

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
  # --clean only drops objects present in the dump. Tables added since the
  # backup can still reference those objects, preventing their removal.
  # Check the dump and permissions before replacing this one database.
  unless system(postgres_environment, "pg_restore", "--list", File.expand_path(transfer_file), out: File::NULL)
    abort "Cannot read the database dump; destination database was not replaced."
  end
  connection = ActiveRecord::Base.connection
  sessions = connection.select_all(<<~SQL).to_a
    SELECT pid, usename, application_name, state
    FROM pg_stat_activity
    WHERE datname = #{connection.quote(database)} AND pid <> pg_backend_pid()
    ORDER BY pid
  SQL
  unless sessions.empty?
    warn "Restore blocked: #{database} has #{sessions.length} other PostgreSQL session(s)."
    sessions.each do |session|
      warn "  PostgreSQL PID #{session.fetch('pid')}: user=#{session['usename'].inspect}, application=#{session['application_name'].inspect}, state=#{session['state'].inspect}"
    end
    abort <<~MESSAGE
      Close Rails servers, Sidekiq, Rails consoles, and database tools using this database.
      VS Code's Ruby LSP Rails helper can keep an idle connection open after bin/dev stops.
      Close VS Code temporarily and rerun the restore from a separate terminal.
      No database or uploaded files have been replaced.
    MESSAGE
  end
  unless connection.select_value("SELECT rolcreatedb OR rolsuper FROM pg_roles WHERE rolname = current_user")
    abort "Restore requires a database role with CREATEDB; destination database was not replaced."
  end
  puts "Recreating destination database: #{database}"
  ActiveRecord::Tasks::DatabaseTasks.purge(configuration.merge(template: "template0"))

  [
    "pg_restore",
    "--no-owner",
    "--no-privileges",
    "--exit-on-error",
    "--single-transaction",
    "--dbname", database,
    File.expand_path(transfer_file)
  ]
end

exec(postgres_environment, *command)
