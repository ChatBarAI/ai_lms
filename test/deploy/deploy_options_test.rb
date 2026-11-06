# Standalone: ruby test/deploy/deploy_options_test.rb (no Rails or SSH connection).
require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require "shellwords"

class DeployOptionsTest < Minitest::Test
  SCRIPT = File.expand_path("../../bin/deploy", __dir__)

  def setup
    @work = Dir.mktmpdir
    File.write("#{@work}/production.key", "test-key")
    @env = {
      "PATH" => "#{@work}:#{ENV.fetch('PATH')}",
      "RAILS_PRODUCTION_KEY_FILE" => "#{@work}/production.key",
      "DEPLOY_ROOT" => "/opt/ai_lms", "SSH_PORT" => "51760",
      "COMMAND_LOG" => "#{@work}/command", "SSH_LOG" => "#{@work}/ssh-arguments"
    }
    stub("git", <<~'SH')
      case "$1" in
        diff) exit 0 ;;
        rev-parse) echo abc123 ;;
        archive) exit 0 ;;
        ls-files) exit 0 ;;
        *) exit 1 ;;
      esac
    SH
    stub("scp", "exit 0")
    stub("ssh", <<~'SH')
      command=${!#}
      case "$command" in
        *'umask 077; mktemp'*) echo /tmp/ai_lms-deploy.TEST1234 ;;
        *'"$release_dir/deploy/server"'*)
          printf '%s' "$command" > "$COMMAND_LOG"
          printf '%s\n' "$@" > "$SSH_LOG"
          ;;
      esac
    SH
  end

  def teardown
    FileUtils.remove_entry(@work)
  end

  def stub(name, body)
    path = "#{@work}/#{name}"
    File.write(path, "#!/usr/bin/env bash\nset -eu\n#{body}\n")
    File.chmod(0o755, path)
  end

  def server_arguments(*options)
    out, err, status = Open3.capture3(@env, "bash", SCRIPT, *options,
      "root@148.72.159.88", "ai-craig-academy.chatbar-ai.com", "alias.example.com")
    assert status.success?, "#{out}\n#{err}"
    command = File.read(@env.fetch("COMMAND_LOG"))
    invocation = command.split('; ').find { |part| part.start_with?('"$release_dir/deploy/server" ') }
    refute_nil invocation
    assert_includes File.read(@env.fetch("SSH_LOG")), "-p\n51760\n"
    Shellwords.split(invocation).drop(1)
  end

  def test_dns_check_is_enabled_by_default
    arguments = server_arguments
    assert_equal "false", arguments[6]
    assert_equal "false", arguments[4]
    assert_equal "/tmp/ai_lms-deploy.TEST1234/production.key", arguments[5]
  end

  def test_skip_option_reaches_server_without_shifting_domains_or_key
    arguments = server_arguments("--skip-dns-check")
    assert_equal "true", arguments[6]
    assert_equal "ai-craig-academy.chatbar-ai.com", arguments[2]
    assert_equal "ai-craig-academy.chatbar-ai.com, alias.example.com", arguments[3]
    assert_equal "/tmp/ai_lms-deploy.TEST1234/production.key", arguments[5]
  end

  def test_skip_combines_with_existing_options
    arguments = server_arguments("--dirty", "--skip-dns-check", "--change-domain")
    assert_equal "true", arguments[4]
    assert_equal "true", arguments[6]
  end
end
