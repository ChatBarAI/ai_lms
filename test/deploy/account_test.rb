# Standalone: ruby test/deploy/account_test.rb (no Rails or database).
require "minitest/autorun"
require "tmpdir"
require "open3"
require "json"
require "rbconfig"

class AccountTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def run_account(arguments, environment = {})
    Dir.mktmpdir do |work|
      File.write("#{work}/ssh", <<~SH)
        #!#{RbConfig.ruby}
        require "json"
        File.write(ENV.fetch("SSH_ARGS"), ARGV.to_json)
        exec #{RbConfig.ruby.dump}, "-r", ENV.fetch("ACCOUNT_STUB"), "-"
      SH
      File.chmod(0o700, "#{work}/ssh")
      File.write("#{work}/stub.rb", <<~'RUBY')
        require "json"
        class User
          def self.where(query, email)
            raise "Wrong duplicate lookup" unless query == "LOWER(email) = ?" && email == email.downcase
            self
          end

          def self.exists?
            ENV["EXISTING"] == "1"
          end

          def initialize(**attributes)
            @attributes = attributes
          end

          def save
            return false if ENV["FAIL_SAVE"] == "1"
            File.write(ENV.fetch("SAVED_USER"), @attributes.to_json)
            true
          end

          def errors
            Struct.new(:full_messages).new(["Email is invalid"])
          end

          def id = 42
          def email = @attributes.fetch(:email)
          def role = @attributes.fetch(:role)
        end
      RUBY
      env = { "PATH" => "#{work}:#{ENV.fetch('PATH')}", "SSH_ARGS" => "#{work}/args.json",
        "ACCOUNT_STUB" => "#{work}/stub.rb", "SAVED_USER" => "#{work}/user.json",
        "SSH_PORT" => nil, "EXISTING" => nil, "FAIL_SAVE" => nil }.merge(environment)
      output, error, status = Open3.capture3(env, RbConfig.ruby, "#{ROOT}/bin/account", *arguments)
      user = JSON.parse(File.read("#{work}/user.json")) if File.exist?("#{work}/user.json")
      ssh_args = JSON.parse(File.read("#{work}/args.json")) if File.exist?("#{work}/args.json")
      yield status, output, error, user, ssh_args
    end
  end

  def test_creates_admin_on_named_instance_and_prints_saved_credentials
    run_account([ "--instance", "staging", "root@85.93.90.221", "--email", " Admin@Example.com " ]) do |status, output, error, user, args|
      assert status.success?, error
      assert_equal "admin@example.com", user.fetch("email")
      assert_equal "admin", user.fetch("role")
      password = output[/^Password: ([a-zA-Z0-9]{24})$/, 1]
      refute_nil password
      assert_equal password, user.fetch("password")
      assert_equal password, user.fetch("password_confirmation")
      assert_includes output, "ID: 42"
      assert_includes args.last, "ai_lms_staging-web-1"
      assert_includes args.last, "bin/rails runner -"
      refute_includes args.join(" "), password
    end
  end

  def test_default_instance_custom_port_and_literal_name
    name = %q[Name ' " $(exit 99) #{abort "injected"}]
    run_account([ "root@example.com", "--email", "student@example.com", "--role", "student", "--name", name ],
      { "SSH_PORT" => "2222" }) do |status, _, error, user, args|
      assert status.success?, error
      assert_equal name, user.fetch("name")
      assert_equal "student", user.fetch("role")
      assert_equal [ "-p", "2222" ], args.first(2)
      assert_includes args.last, "ai_lms-web-1"
    end
  end

  def test_duplicate_email_is_not_overwritten
    run_account([ "root@example.com", "--email", "admin@example.com" ], { "EXISTING" => "1" }) do |status, output, error, user, _|
      refute status.success?
      assert_includes error, "already exists; no changes made"
      assert_nil user
      refute_includes output, "Password:"
    end
  end

  def test_validation_failure_does_not_print_credentials
    run_account([ "root@example.com", "--email", "invalid" ], { "FAIL_SAVE" => "1" }) do |status, output, error, user, _|
      refute status.success?
      assert_includes error, "Email is invalid"
      assert_nil user
      refute_includes output, "Account created."
      refute_includes output, "Password:"
    end
  end

  def test_invalid_arguments_never_connect
    [ [ "root@example.com" ], [ "-bad", "--email", "a@example.com" ],
      [ "root@example.com", "--email", "a@example.com", "--instance", "edge" ],
      [ "root@example.com", "--email", "a@example.com", "--instance", "../staging" ],
      [ "root@example.com", "--email", "a@example.com", "--role", "owner" ],
      [ "root@example.com", "extra", "--email", "a@example.com" ] ].each do |arguments|
      run_account(arguments) do |status, _, _, user, args|
        assert_equal 2, status.exitstatus
        assert_nil user
        assert_nil args
      end
    end
  end

  def test_invalid_port_never_connects
    run_account([ "root@example.com", "--email", "a@example.com" ], { "SSH_PORT" => "0" }) do |status, _, _, user, args|
      assert_equal 2, status.exitstatus
      assert_nil user
      assert_nil args
    end
  end

  def test_help_does_not_connect
    run_account([ "--help" ]) do |status, output, _, user, args|
      assert status.success?
      assert_includes output, "Usage: bin/account"
      assert_nil user
      assert_nil args
    end
  end
end
