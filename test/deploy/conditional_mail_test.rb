# Run the real deployment selection block with a fake Docker CLI; no Rails/SSH.
require "minitest/autorun"
require "tmpdir"
require "open3"

class ConditionalMailDeploymentTest < Minitest::Test
  def run_selection(mode, fail_mail: false)
    Dir.mktmpdir do |dir|
      log = File.join(dir, "calls")
      env_file = File.join(dir, "env")
      File.write(env_file, "COMPOSE_PROFILES=local-mail\n")
      docker = File.join(dir, "docker")
      File.write(docker, <<~'SH')
        #!/bin/sh
        printf '%s\n' "$*" >> "$CALL_LOG"
        case "$*" in
          *'runner deploy/mail_mode.rb') printf 'LMS_MAIL_MODE=%s\n' "$TEST_MAIL_MODE" ;;
          *'build mail') [ "$FAIL_MAIL" != true ] || exit 12 ;;
        esac
        exit 0
      SH
      File.chmod(0o755, docker)
      server = File.read(File.expand_path("../../deploy/server", __dir__))
      block = server.split('compose=(docker compose --env-file "$env_file" -f "$release_dir/compose.yaml")', 2).last.split('if $domain_changed;', 2).first
      script = "set -Eeuo pipefail\ncompose=(docker compose --env-file \"$env_file\" -f \"$release_dir/compose.yaml\")\n#{block}"
      out, err, status = Open3.capture3({ "PATH" => "#{dir}:#{ENV.fetch('PATH')}",
        "env_file" => env_file, "release_dir" => dir, "CALL_LOG" => log,
        "TEST_MAIL_MODE" => mode, "FAIL_MAIL" => fail_mail.to_s }, "bash", "-c", script)
      yield status, File.read(log), File.read(env_file), out + err
    end
  end

  def test_external_mail_skips_even_a_broken_postfix_build
    run_selection("external", fail_mail: true) do |status, calls, env, output|
      assert status.success?, output
      refute_includes calls, "build mail"
      refute_match(/--wait-timeout 150 mail/, calls)
      assert_includes env, "COMPOSE_PROFILES=\n"
      assert_includes env, "COMPOSE_FILE=compose.yaml\n"
      refute_includes calls, "compose.mail.yaml"
    end
  end

  def test_local_mail_builds_and_waits_after_database_bootstrap
    run_selection("local") do |status, calls, env, output|
      assert status.success?, output
      assert_operator calls.index("build mail"), :>, calls.index("runner deploy/configure_mail.rb")
      assert_includes calls, "up -d --wait --wait-timeout 150 mail"
      assert_includes env, "COMPOSE_PROFILES=local-mail\n"
      assert_includes env, "COMPOSE_FILE=compose.yaml:compose.mail.yaml\n"
      assert_includes calls.lines.find { |line| line.include?("build mail") }, "compose.mail.yaml"
    end
  end

  def test_local_mail_still_requires_successful_build
    run_selection("local", fail_mail: true) { |status, *_| refute status.success? }
  end

  def test_unknown_selection_fails_closed
    run_selection("unknown") do |status, calls, _, _output|
      refute status.success?
      refute_includes calls, "build mail"
    end
  end
end
