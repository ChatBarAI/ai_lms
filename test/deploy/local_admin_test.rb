# Standalone: ruby test/deploy/local_admin_test.rb (no Rails or database).
require "minitest/autorun"
require "tmpdir"
require "open3"
require "json"
require "rbconfig"

class LocalAdminTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def run_admin(answer: "yes\n", operation: "--ask", rails_env: "development", initial: {}, database: {}, environment: {})
    Dir.mktmpdir do |work|
      File.write("#{work}/stub.rb", <<~'RUBY')
        require "json"
        module Rails
          def self.env
            Struct.new(:name) do
              def development?
                name == "development"
              end
            end.new(ENV.fetch("APP_ENV"))
          end
        end
        module ActiveRecord
          class Base
            def self.connection_db_config
              Struct.new(:configuration_hash).new(JSON.parse(ENV.fetch("DB_CONFIG"), symbolize_names: true))
            end
          end
        end
        class User
          def self.find_or_initialize_by(email:)
            new(email)
          end

          def initialize(email)
            @attributes = JSON.parse(ENV.fetch("USER_INITIAL")).merge("email" => email)
          end

          def name
            @attributes["name"]
          end

          def name=(name)
            @attributes["name"] = name
          end

          def assign_attributes(attributes)
            @attributes.merge!(attributes.transform_keys(&:to_s))
          end

          def save!
            raise "Validation failed" if ENV["FAIL_SAVE"] == "1"
            File.write(ENV.fetch("SAVED_USER"), @attributes.to_json)
          end
        end
      RUBY
      configuration = { database: "ai_lms_development", host: "localhost" }.merge(database)
      variables = { "APP_ENV" => rails_env, "DB_CONFIG" => configuration.to_json,
        "USER_INITIAL" => initial.to_json, "SAVED_USER" => "#{work}/user.json",
        "SEED_ADMIN_EMAIL" => nil, "SEED_ADMIN_PASSWORD" => nil, "PGHOST" => nil,
        "PGHOSTADDR" => nil, "PGSERVICE" => nil, "FAIL_SAVE" => nil }.merge(environment)
      output, error, status = Open3.capture3(variables, RbConfig.ruby, "-r", "#{work}/stub.rb",
        "#{ROOT}/deploy/local_admin.rb", operation, stdin_data: answer)
      saved_user = File.exist?("#{work}/user.json") ? JSON.parse(File.read("#{work}/user.json")) : nil
      yield status, output, error, saved_user
    end
  end

  def test_yes_creates_an_admin_with_a_generated_password
    run_admin(answer: " Yes \n") do |status, output, error, user|
      assert status.success?, error
      assert_includes output, "Create or reset local admin admin@example.com? [y/N]"
      password = output[/Generated password: ([a-zA-Z0-9]{20})/, 1]
      refute_nil password
      assert_equal "admin@example.com", user.fetch("email")
      assert_equal "Admin", user.fetch("name")
      assert_equal "admin", user.fetch("role")
      assert_equal password, user.fetch("password")
      assert_equal password, user.fetch("password_confirmation")
      assert_equal 0, user.fetch("failed_attempts")
    end
  end

  def test_existing_account_is_unlocked_and_reset_without_printing_supplied_password
    initial = { name: "Existing Admin", role: "student", failed_attempts: 20,
      locked_at: "yesterday", unlock_token: "old", reset_password_token: "old",
      reset_password_sent_at: "yesterday", remember_created_at: "yesterday" }
    run_admin(initial: initial, environment: { "SEED_ADMIN_EMAIL" => " Local@Example.com ",
      "SEED_ADMIN_PASSWORD" => "chosen-password-123" }) do |status, output, error, user|
      assert status.success?, error
      assert_equal "local@example.com", user.fetch("email")
      assert_equal "Existing Admin", user.fetch("name")
      assert_equal "admin", user.fetch("role")
      assert_equal "chosen-password-123", user.fetch("password")
      assert_equal 0, user.fetch("failed_attempts")
      %w[locked_at unlock_token reset_password_token reset_password_sent_at remember_created_at].each do |field|
        assert_nil user.fetch(field)
      end
      assert_includes output, "Password: supplied via SEED_ADMIN_PASSWORD"
      refute_includes output + error, "chosen-password-123"
    end
  end

  def test_no_blank_invalid_answer_and_eof_leave_accounts_unchanged
    [ "no\n", "\n", "maybe\n", "" ].each do |answer|
      run_admin(answer: answer) do |status, output, error, user|
        assert status.success?, error
        assert_includes output, "Local admin setup skipped."
        assert_nil user
        refute_includes output, "Generated password"
      end
    end
  end

  def test_check_only_does_not_prompt_or_change_accounts
    run_admin(operation: "--check") do |status, output, error, user|
      assert status.success?, error
      assert_empty output
      assert_nil user
    end
  end

  def test_create_mode_supports_the_existing_noninteractive_pull
    run_admin(operation: "--create", answer: "") do |status, output, error, user|
      assert status.success?, error
      refute_includes output, "[y/N]"
      assert_equal "admin", user.fetch("role")
    end
  end

  def test_nonlocal_or_non_development_targets_are_rejected_before_the_prompt
    [ { rails_env: "production" }, { rails_env: "test" },
      { database: { database: "ai_lms_production" } }, { database: { host: "remote.example.com" } },
      { database: { host: "/var/run/postgresql,remote.example.com" } },
      { environment: { "PGHOSTADDR" => "203.0.113.1" } }, { environment: { "PGSERVICE" => "remote" } },
      { database: { hostaddr: "203.0.113.1" } }, { database: { service: "remote" } }
    ].each do |options|
      run_admin(**options) do |status, output, _, user|
        refute status.success?, options.inspect
        refute_includes output, "[y/N]"
        assert_nil user
      end
    end
  end

  def test_failed_save_does_not_print_login_credentials
    run_admin(environment: { "FAIL_SAVE" => "1" }) do |status, output, _, user|
      refute status.success?
      assert_nil user
      refute_includes output, "Generated password"
      refute_includes output, "Local admin:"
    end
  end
end
