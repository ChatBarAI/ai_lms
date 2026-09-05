# Standalone: ruby test/deploy/backup_test.rb (does not boot Rails).
require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"

class BackupScriptTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def test_success_and_failed_dump
    [false, true].each do |fail_dump|
      Dir.mktmpdir do |work|
        FileUtils.mkdir_p("#{work}/shared")
        FileUtils.touch("#{work}/shared/.env")
        File.write("#{work}/docker", <<~'SH')
          #!/usr/bin/env bash
          set -eu
          echo "$*" >> "$CALL_LOG"
          case " $* " in
            *' ps '*) echo web ;;
            *' pg_dump '*)
              [[ $FAIL_DUMP != 1 ]] || exit 1
              printf 'PGDMP fixture'
              ;;
            *)
              if [[ $1 == run ]]; then
                for arg in "$@"; do
                  if [[ $arg == *:/backup ]]; then
                    tar -czf "${arg%:/backup}/storage.tar.gz" --files-from /dev/null
                  fi
                done
              fi
              ;;
          esac
        SH
        File.chmod(0o755, "#{work}/docker")
        output = "#{work}/backup.tar.gz"
        environment = {
          "PATH" => "#{work}:#{ENV.fetch('PATH')}", "DEPLOY_ROOT" => work,
          "DEPLOY_MODE" => "docker", "CALL_LOG" => "#{work}/calls",
          "FAIL_DUMP" => fail_dump ? "1" : "0"
        }
        _, error, status = Open3.capture3(environment, "#{ROOT}/deploy/backup", output)
        assert_equal !fail_dump, status.success?, error
        calls = File.read("#{work}/calls")
        assert_includes calls, "stop web\n"
        assert_includes calls, "start web\n"
        refute_includes calls, "start web worker"
        assert_equal !fail_dump, File.exist?(output)
        assert_empty Dir.glob("#{work}/.ai-lms-backup.*")
        next if fail_dump

        assert_equal 0o600, File.stat(output).mode & 0o777
        entries, error, status = Open3.capture3("tar", "-tzf", output)
        assert status.success?, error
        assert_equal %w[database.dump metadata storage.tar.gz], entries.lines.map(&:strip).sort
        original = File.binread(output)
        _, _, status = Open3.capture3(environment, "#{ROOT}/deploy/backup", output)
        refute status.success?
        assert_equal original, File.binread(output)
      end
    end
  end
end
