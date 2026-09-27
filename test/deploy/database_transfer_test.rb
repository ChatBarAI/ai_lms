# Standalone: ruby test/deploy/database_transfer_test.rb (no Rails or database).
require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require "json"
require "rbconfig"

class DatabaseTransferTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  CONFIGURATION = { "adapter" => "postgresql", "database" => "destination_development",
    "host" => "localhost", "port" => 5433, "username" => "local_owner", "encoding" => "unicode" }.freeze

  def run_transfer(operation: "restore", failure: nil, sessions: [])
    Dir.mktmpdir do |work|
      File.write("#{work}/active_record_stub.rb", <<~'RUBY')
        require "json"
        module ActiveRecord
          class Base
            def self.connection_db_config
              Struct.new(:configuration_hash).new(JSON.parse(ENV.fetch("DB_CONFIG"), symbolize_names: true))
            end

            def self.connection
              self
            end

            def self.select_value(_sql)
              ENV["FAILURE"] != "permission"
            end

            def self.quote(value)
              "'#{value.gsub("'", "''")}'"
            end

            def self.select_all(sql)
              File.write(ENV.fetch("QUERY_LOG"), sql)
              raise "Cannot check PostgreSQL sessions" if ENV["FAILURE"] == "sessions"
              JSON.parse(ENV.fetch("SESSIONS"))
            end
          end

          module Tasks
            module DatabaseTasks
              def self.purge(configuration)
                File.open(ENV.fetch("CALL_LOG"), "a") { |file| file.puts "purge #{configuration.to_json}" }
                raise "Cannot drop destination database" if ENV["FAILURE"] == "purge"
              end
            end
          end
        end
      RUBY
      %w[pg_dump pg_restore].each do |command|
        File.write("#{work}/#{command}", <<~'SH')
          #!/usr/bin/env bash
          set -eu
          echo "${0##*/} $* host=$PGHOST port=$PGPORT user=$PGUSER" >> "$CALL_LOG"
          if [[ ${1:-} == --list && ${FAILURE:-} == list ]]; then exit 1; fi
          if [[ ${1:-} != --list && ${FAILURE:-} == restore ]]; then exit 1; fi
        SH
        File.chmod(0o755, "#{work}/#{command}")
      end
      environment = { "PATH" => "#{work}:#{ENV.fetch('PATH')}", "CALL_LOG" => "#{work}/calls",
        "DB_CONFIG" => CONFIGURATION.to_json, "FAILURE" => failure,
        "QUERY_LOG" => "#{work}/query", "SESSIONS" => sessions.to_json }
      _, error, status = Open3.capture3(environment, RbConfig.ruby, "-r", "#{work}/active_record_stub.rb",
        "#{ROOT}/deploy/database_transfer.rb", operation, "#{work}/backup with spaces.dump")
      query = File.exist?("#{work}/query") ? File.read("#{work}/query") : ""
      yield status, error, File.read("#{work}/calls"), query
    end
  end

  def test_restore_checks_dump_then_recreates_only_destination_before_importing
    run_transfer do |status, error, calls, query|
      assert status.success?, error
      lines = calls.lines
      assert_match(/\Apg_restore --list /, lines[0])
      assert_equal CONFIGURATION.merge("template" => "template0"), JSON.parse(lines[1].delete_prefix("purge "))
      assert_match(/\Apg_restore --no-owner /, lines[2])
      assert_includes lines[2], "--dbname destination_development"
      assert_includes lines[2], "--single-transaction"
      assert_includes lines[2], "host=localhost port=5433 user=local_owner"
      refute_includes calls, "--create"
      refute_includes calls, "--clean"
      assert_equal 3, lines.size
      assert_includes query, "WHERE datname = 'destination_development' AND pid <> pg_backend_pid()"
      refute_match(/state\s*=/, query)
    end
  end

  def test_other_sessions_block_restore_and_identify_idle_editor_helpers
    sessions = [
      { pid: 25203, usename: "local_owner", application_name: "bin/rails", state: "idle" },
      { pid: 25204, usename: "another_user", application_name: "psql", state: "active" },
      { pid: 25205, usename: "restricted_user", application_name: nil, state: nil }
    ]
    run_transfer(sessions: sessions) do |status, error, calls|
      refute status.success?
      assert_includes error, "Restore blocked: destination_development has 3 other PostgreSQL session(s)."
      assert_includes error, 'PostgreSQL PID 25203: user="local_owner", application="bin/rails", state="idle"'
      assert_includes error, 'PostgreSQL PID 25204: user="another_user", application="psql", state="active"'
      assert_includes error, "PostgreSQL PID 25205"
      assert_includes error, "VS Code's Ruby LSP Rails helper"
      assert_includes error, "No database or uploaded files have been replaced."
      refute_includes calls, "purge"
      refute_includes calls, "--dbname"
    end
  end

  def test_failed_connection_check_never_purges_or_imports
    run_transfer(failure: "sessions") do |status, error, calls|
      refute status.success?
      assert_includes error, "Cannot check PostgreSQL sessions"
      refute_includes calls, "purge"
      refute_includes calls, "--dbname"
    end
  end

  def test_unreadable_dump_or_insufficient_permissions_never_purge
    %w[list permission].each do |failure|
      run_transfer(failure: failure) do |status, error, calls|
        refute status.success?
        assert_includes error, "destination database was not replaced"
        assert_equal 1, calls.lines.size
        refute_includes calls, "purge"
      end
    end
  end

  def test_failed_purge_never_imports
    run_transfer(failure: "purge") do |status, error, calls|
      refute status.success?
      assert_includes error, "Cannot drop destination database"
      refute_includes calls, "--dbname"
    end
  end

  def test_failed_import_returns_failure
    run_transfer(failure: "restore") do |status, _, calls|
      refute status.success?
      assert_includes calls, "--dbname destination_development"
    end
  end

  def test_dump_does_not_recreate_database
    run_transfer(operation: "dump") do |status, error, calls|
      assert status.success?, error
      assert_match(/\Apg_dump --format=custom /, calls)
      assert_equal 1, calls.lines.size
      refute_includes calls, "purge"
      refute_includes calls, "pg_restore"
    end
  end
end
