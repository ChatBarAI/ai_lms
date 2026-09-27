# Standalone: ruby test/deploy/restore_test.rb (no Rails, Docker, or database).
require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"

class RestoreScriptTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def run_restore(failure: nil, ask_admin: false)
    Dir.mktmpdir do |work|
      FileUtils.mkdir_p("#{work}/shared")
      FileUtils.touch("#{work}/shared/.env")
      File.write("#{work}/docker", <<~'SH')
        #!/usr/bin/env bash
        set -eu
        echo "$*" >> "$CALL_LOG"
        case " $* " in
          *' pg_restore --list '*) cat >/dev/null; [[ ${FAILURE:-} != list ]] ;;
          *' psql '*)
            [[ ${FAILURE:-} != session_check ]] || exit 1
            if [[ ${FAILURE:-} == sessions ]]; then
              echo "PostgreSQL PID 25203: user='ai_lms', application='bin/rails', state='idle'"
            fi
            ;;
          *' dropdb '*) [[ ${FAILURE:-} != drop ]] ;;
          *' createdb '*) [[ ${FAILURE:-} != create ]] ;;
          *' pg_restore '*) cat >/dev/null; [[ ${FAILURE:-} != restore ]] ;;
        esac
      SH
      File.chmod(0o755, "#{work}/docker")
      bundle = create_bundle(work)
      environment = { "PATH" => "#{work}:#{ENV.fetch('PATH')}", "DEPLOY_ROOT" => work,
        "DEPLOY_MODE" => "docker", "CALL_LOG" => "#{work}/calls", "FAILURE" => failure,
        "PRESERVE_INSTANCE_SETTINGS" => "0" }
      arguments = [ "--force" ]
      arguments << "--ask-admin" if ask_admin
      _, error, status = Open3.capture3(environment, "#{ROOT}/deploy/restore", *arguments, bundle)
      calls = File.exist?("#{work}/calls") ? File.read("#{work}/calls") : ""
      yield status, error, calls
    end
  end

  def create_bundle(work)
    File.write("#{work}/metadata", "format=ai_lms_clone_v1\n")
    File.write("#{work}/database.dump", "PGDMP fixture")
    system("tar", "-czf", "#{work}/storage.tar.gz", "--files-from", "/dev/null", exception: true)
    bundle = "#{work}/bundle.tar.gz"
    system("tar", "-czf", bundle, "-C", work, "metadata", "database.dump", "storage.tar.gz", exception: true)
    bundle
  end

  def test_restores_into_empty_destination_before_replacing_uploads
    run_restore do |status, error, calls|
      assert status.success?, error
      sequence = [ "stop web worker proxy", "pg_restore --list", "psql -X --set=ON_ERROR_STOP=1", "dropdb --if-exists -U ai_lms ai_lms_production",
        "createdb --template=template0 -U ai_lms ai_lms_production", "pg_restore --no-owner", "find /target",
        "./bin/rails db:migrate", "SiteSetting.update_all", "up -d web worker proxy" ]
      sequence.each { |command| assert_includes calls, command }
      sequence.each_cons(2) { |before, after| assert_operator calls.index(before), :<, calls.index(after) }
      assert_includes calls, "--single-transaction"
      refute_includes calls, "--clean"
      refute_includes calls, "--create "
      assert_includes calls, "WHERE datname = 'ai_lms_production' AND pid <> pg_backend_pid()"
    end
  end

  def test_failures_stop_before_upload_replacement_and_leave_services_stopped
    %w[list sessions session_check drop create restore].each do |failure|
      run_restore(failure: failure) do |status, error, calls|
        refute status.success?, failure
        refute_includes calls, "find /target"
        refute_includes calls, "db:migrate"
        refute_includes calls, "up -d web worker proxy"
        refute_includes calls, "dropdb" if %w[list sessions session_check].include?(failure)
        refute_includes calls, "createdb" if failure == "drop"
        refute_includes calls, "pg_restore --no-owner" if failure == "create"
        if failure == "sessions"
          assert_includes error, "Restore blocked"
          assert_includes error, "PostgreSQL PID 25203"
          assert_includes error, "No database or uploaded files have been replaced."
        end
      end
    end
  end

  def run_native_restore(ask_admin: false, failure: nil, rails_env: "development")
    Dir.mktmpdir do |work|
      %w[app/bin app/deploy app/storage tools].each { |dir| FileUtils.mkdir_p("#{work}/#{dir}") }
      %w[restore unpack-bundle].each { |file| FileUtils.cp("#{ROOT}/deploy/#{file}", "#{work}/app/deploy/#{file}") }
      File.write("#{work}/app/storage/existing-upload", "keep this upload")
      File.write("#{work}/app/bin/rails", <<~'SH')
        #!/usr/bin/env bash
        set -eu
        echo "$*" >> "$CALL_LOG"
        case "$*" in
          'runner deploy/local_admin.rb --check') [[ ${FAILURE:-} != admin_check ]] ;;
          'runner deploy/database_transfer.rb restore '*)
            if [[ ${FAILURE:-} == database ]]; then
              echo 'Restore blocked: another PostgreSQL session is connected.' >&2
              exit 1
            fi
            ;;
          'db:migrate') [[ ${FAILURE:-} != migrate ]] ;;
          'runner SiteSetting.update_all'*) [[ ${FAILURE:-} != settings ]] ;;
          'runner deploy/local_admin.rb --ask') [[ ${FAILURE:-} != admin ]] ;;
        esac
      SH
      File.write("#{work}/tools/pg_restore", "#!/usr/bin/env bash\nexit 0\n")
      File.chmod(0o755, "#{work}/app/bin/rails", "#{work}/tools/pg_restore")
      environment = { "PATH" => "#{work}/tools:#{ENV.fetch('PATH')}", "DEPLOY_MODE" => "native",
        "RAILS_ENV" => rails_env, "NATIVE_WRITES_STOPPED" => "1", "STORAGE_PATH" => "#{work}/app/storage",
        "PRESERVE_INSTANCE_SETTINGS" => "0", "CALL_LOG" => "#{work}/calls", "FAILURE" => failure }
      arguments = [ "--force" ]
      arguments << "--ask-admin" if ask_admin
      output, error, status = Open3.capture3(environment, "#{work}/app/deploy/restore", *arguments, create_bundle(work))
      calls = File.exist?("#{work}/calls") ? File.read("#{work}/calls") : ""
      yield status, error, calls, work, output
    end
  end

  def test_native_database_check_failure_preserves_uploads_and_skips_migrations
    run_native_restore(failure: "database") do |status, error, calls, work|
      refute status.success?
      assert_includes error, "Restore blocked"
      assert_equal "keep this upload", File.read("#{work}/app/storage/existing-upload")
      assert_equal 1, calls.lines.size
      assert_includes calls, "runner deploy/database_transfer.rb restore"
      refute_includes calls, "db:migrate"
    end
  end

  def test_admin_option_checks_destination_first_and_prompts_only_after_migrations_and_settings
    run_native_restore(ask_admin: true) do |status, error, calls, _, output|
      assert status.success?, error
      sequence = [ "local_admin.rb --check", "database_transfer.rb restore", "db:migrate",
        "SiteSetting.update_all", "local_admin.rb --ask" ]
      sequence.each { |command| assert_includes calls, command }
      sequence.each_cons(2) { |before, after| assert_operator calls.index(before), :<, calls.index(after) }
      assert_includes output, "Clone restored successfully."
    end
  end

  def test_admin_prompt_is_optional
    run_native_restore do |status, error, calls|
      assert status.success?, error
      refute_includes calls, "local_admin.rb"
    end
  end

  def test_admin_prompt_never_runs_after_a_failed_restore
    %w[admin_check database migrate settings].each do |failure|
      run_native_restore(ask_admin: true, failure: failure) do |status, _, calls|
        refute status.success?, failure
        refute_includes calls, "local_admin.rb --ask"
        refute_includes calls, "database_transfer.rb restore" if failure == "admin_check"
      end
    end
  end

  def test_admin_failure_explains_how_to_retry_without_restoring
    run_native_restore(ask_admin: true, failure: "admin") do |status, error, _, _, output|
      refute status.success?
      assert_includes output, "Clone restored successfully."
      assert_includes error, "The restore completed, but local admin setup failed."
      assert_includes error, "bin/rails runner deploy/local_admin.rb --ask"
    end
  end

  def test_admin_option_rejects_production_and_docker_before_modifying_data
    run_native_restore(ask_admin: true, rails_env: "production") do |status, error, calls, work|
      refute status.success?
      assert_includes error, "only supported for native restores with RAILS_ENV=development"
      assert_empty calls
      assert_equal "keep this upload", File.read("#{work}/app/storage/existing-upload")
    end
    run_restore(ask_admin: true) do |status, error, calls|
      refute status.success?
      assert_includes error, "only supported for native restores"
      assert_empty calls
    end
  end
end
