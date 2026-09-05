# Standalone: ruby test/deploy/remote_transfer_test.rb (no network or Rails).
require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"

class RemoteTransferTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def with_transport(fail_download: false)
    Dir.mktmpdir do |work|
      File.write("#{work}/ssh", <<~'SH')
        #!/usr/bin/env bash
        echo "ssh $*" >> "$CALL_LOG"
        if [[ $* == *'mktemp -d'* ]]; then
          echo /tmp/ai_lms-transfer.ABC12345
        fi
      SH
      File.write("#{work}/scp", <<~'SH')
        #!/usr/bin/env bash
        echo "scp $*" >> "$CALL_LOG"
        if [[ ${@: -2:1} == *@*:* ]]; then
          [[ $FAIL_DOWNLOAD != 1 ]] || exit 1
          printf 'archive fixture' > "${@: -1}"
        fi
      SH
      FileUtils.chmod(0o755, ["#{work}/ssh", "#{work}/scp"])
      environment = {
        "PATH" => "#{work}:#{ENV.fetch('PATH')}", "CALL_LOG" => "#{work}/calls",
        "SSH_PORT" => "51760", "DEPLOY_ROOT" => "/opt/custom_lms",
        "FAIL_DOWNLOAD" => fail_download ? "1" : "0"
      }
      yield work, environment
    end
  end

  def test_backup_and_export_download_without_overwrite
    %w[backup export].each do |operation|
      with_transport do |work, environment|
        output = "#{work}/archive with spaces.tar.gz"
        _, error, status = Open3.capture3(environment, "#{ROOT}/bin/#{operation}", "root@example.com", output)
        assert status.success?, error
        assert_equal "archive fixture", File.read(output)
        assert_equal 0o600, File.stat(output).mode & 0o777
        calls = File.read("#{work}/calls")
        assert_includes calls, "ssh -p 51760"
        assert_includes calls, "scp -P 51760"
        assert_includes calls, "/opt/custom_lms/current/deploy/export"
        refute_includes calls, "/opt/custom_lms/current/deploy/backup"
        assert_includes calls, "test -f '/tmp/ai_lms-transfer.ABC12345/bundle.tar.gz'"
        assert_includes calls, "rm -f '/tmp/ai_lms-transfer.ABC12345/bundle.tar.gz'"
        _, _, status = Open3.capture3(environment, "#{ROOT}/bin/#{operation}", "root@example.com", output)
        refute status.success?
        assert_equal calls, File.read("#{work}/calls")
      end
    end
  end

  def test_failed_download_retains_remote_archive_and_no_local_output
    with_transport(fail_download: true) do |work, environment|
      output = "#{work}/archive.tar.gz"
      _, error, status = Open3.capture3(environment, "#{ROOT}/bin/backup", "root@example.com", output)
      refute status.success?
      refute File.exist?(output)
      assert_empty Dir.glob("#{work}/.ai-lms-download.*")
      assert_includes error, "retained for recovery"
      refute_includes File.read("#{work}/calls"), "rm -f"
    end
  end

  def test_restore_requires_force_then_uploads_and_restores
    with_transport do |work, environment|
      archive = "#{work}/input.tar.gz"
      File.write(archive, "fixture")
      _, _, status = Open3.capture3(environment, "#{ROOT}/bin/restore", "root@example.com", archive)
      refute status.success?
      refute File.exist?("#{work}/calls")
      _, error, status = Open3.capture3(environment, "#{ROOT}/bin/restore", "--force", "root@example.com", archive)
      assert status.success?, error
      calls = File.read("#{work}/calls")
      assert_includes calls, "scp -P 51760"
      assert_includes calls, "/deploy/restore' --force '/tmp/ai_lms-transfer.ABC12345/bundle.tar.gz'"
    end
  end

  def test_invalid_host_and_port_do_not_connect
    with_transport do |work, environment|
      [ ["-oProxyCommand=bad", "22"], ["root@example.com", "invalid"] ].each do |host, port|
        _, _, status = Open3.capture3(environment.merge("SSH_PORT" => port), "#{ROOT}/bin/backup", host)
        refute status.success?
        refute File.exist?("#{work}/calls")
      end
    end
  end
end
