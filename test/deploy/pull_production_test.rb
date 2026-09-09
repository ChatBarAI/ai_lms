# Standalone: ruby test/deploy/pull_production_test.rb (no Rails or network).
require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"

class PullProductionTest < Minitest::Test
  def run_pull(fail_download: false, fail_restore: false, stopped: "1")
    Dir.mktmpdir do |root|
      %w[bin deploy tools].each { |dir| FileUtils.mkdir_p("#{root}/#{dir}") }
      FileUtils.cp(File.expand_path("../../bin/pull-production", __dir__), "#{root}/bin/pull-production")
      scripts = {
        "tools/ssh" => 'echo "ssh $*" >> "$CALL_LOG"; [[ $* != *mktemp* ]] || echo /tmp/ai_lms-pull.ABC12345',
        "tools/scp" => 'echo scp >> "$CALL_LOG"; [[ $FAIL_DOWNLOAD != 1 ]] || exit 1; touch "${@: -1}"',
        "tools/pg_dump" => 'exit 0',
        "tools/pg_restore" => 'exit 0',
        "bin/rails" => 'echo "rails $1 env=$RAILS_ENV" >> "$CALL_LOG"',
        "deploy/export" => 'echo "backup env=$RAILS_ENV mode=$DEPLOY_MODE" >> "$CALL_LOG"; touch "$1"',
        "deploy/restore" => 'echo "restore env=$RAILS_ENV mode=$DEPLOY_MODE $1" >> "$CALL_LOG"; [[ $FAIL_RESTORE != 1 ]]'
      }
      scripts.each do |path, body|
        File.write("#{root}/#{path}", "#!/usr/bin/env bash\nset -e\n#{body}\n")
        FileUtils.chmod(0o755, "#{root}/#{path}")
      end
      env = { "PATH" => "#{root}/tools:#{ENV.fetch('PATH')}", "CALL_LOG" => "#{root}/calls",
              "NATIVE_WRITES_STOPPED" => stopped, "FAIL_DOWNLOAD" => fail_download ? "1" : "0",
              "FAIL_RESTORE" => fail_restore ? "1" : "0",
              "DATABASE_URL" => nil, "PGSERVICE" => nil, "PGHOSTADDR" => nil, "SSH_PORT" => "2222" }
      _, error, status = Open3.capture3(env, "bash", "#{root}/bin/pull-production", "--force", "bl@example.com", "/srv/ai_lms")
      calls = File.exist?("#{root}/calls") ? File.read("#{root}/calls") : ""
      yield status, error, calls, root
    end
  end

  def test_native_pull_backs_up_before_restoring_in_development
    run_pull do |status, error, calls, root|
      assert status.success?, error
      assert_includes calls, "DEPLOY_MODE=native RAILS_ENV=production"
      assert_includes calls, "ssh -p 2222"
      assert_includes calls, "backup env=development mode=native"
      assert_includes calls, "restore env=development mode=native --force"
      assert_operator calls.index("backup env="), :<, calls.index("restore env=")
      assert_operator calls.index("restore env="), :<, calls.rindex("rails runner env=development")
      assert_equal 2, calls.scan("rails runner env=development").length
      assert_equal 1, Dir.glob("#{root}/tmp/production-pulls/*/development-before.tar.gz").length
    end
  end

  def test_download_failure_never_modifies_local_data_or_deletes_remote_snapshot
    run_pull(fail_download: true) do |status, error, calls, _|
      refute status.success?
      refute_includes calls, "rails db:create"
      refute_includes calls, "restore env="
      refute_includes calls, "rm -f"
      assert_includes error, "Remote snapshot staging retained"
    end
  end

  def test_requires_stopped_writers_before_any_commands
    run_pull(stopped: "0") do |status, _, calls, _|
      refute status.success?
      assert_empty calls
    end
  end

  def test_failed_restore_does_not_reset_admin
    run_pull(fail_restore: true) do |status, _, calls, _|
      refute status.success?
      assert_equal 1, calls.scan("rails runner env=development").length
    end
  end
end
