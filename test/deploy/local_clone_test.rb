require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"

class LocalCloneTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def test_isolated_restore_and_invalid_bundle
    Dir.mktmpdir do |work|
      File.write("#{work}/docker", <<~'SH')
        #!/usr/bin/env bash
        echo "$*" >> "$CALL_LOG"
        if [[ $* == 'context inspect'* ]]; then echo unix:///var/run/docker.sock; fi
        case "$*" in
          *'exec -T db pg_restore'*|*'--entrypoint /bin/sh'*) cat >/dev/null ;;
        esac
      SH
      File.chmod(0o755, "#{work}/docker")
      FileUtils.mkdir_p("#{work}/app/bin")
      FileUtils.mkdir_p("#{work}/app/deploy")
      FileUtils.cp("#{ROOT}/bin/local-clone", "#{work}/app/bin/local-clone")
      FileUtils.cp("#{ROOT}/deploy/unpack-bundle", "#{work}/app/deploy/unpack-bundle")
      environment = { "DOCKER_CONTEXT" => nil, "DOCKER_HOST" => nil,
        "PATH" => "#{work}:#{ENV.fetch('PATH')}", "CALL_LOG" => "#{work}/calls" }
      File.write("#{work}/metadata", "format=ai_lms_clone_v1\n")
      File.write("#{work}/database.dump", "PGDMP fixture")
      system("tar", "-czf", "#{work}/storage.tar.gz", "--files-from", "/dev/null", exception: true)
      bundle = "#{work}/bundle.tar.gz"
      system("tar", "-czf", bundle, "-C", work, "metadata", "database.dump", "storage.tar.gz", exception: true)
      _, error, status = Open3.capture3(environment, "#{work}/app/bin/local-clone", "restore", "--force", bundle)
      assert status.success?, error
      calls = File.read("#{work}/calls")
      calls.lines.reject { |line| line.start_with?("context inspect") }.each do |line|
        assert_includes line, "--project-name ai_lms_local_clone"
        assert_includes line, "compose.local.yaml"
      end
      assert_operator calls.index("pg_restore --list"), :<, calls.index("dropdb")
      assert_includes calls, "up -d --wait web"
      refute_includes calls, "worker"
      File.write("#{work}/storage.tar.gz", "corrupt")
      system("tar", "-czf", bundle, "-C", work, "metadata", "database.dump", "storage.tar.gz", exception: true)
      _, _, status = Open3.capture3(environment, "#{work}/app/bin/local-clone", "restore", "--force", bundle)
      refute status.success?
      assert_equal calls.lines.grep(/compose/), File.read("#{work}/calls").lines.grep(/compose/)
      secret = File.read("#{work}/app/.env.local-clone-secret")
      assert_match(/\A[a-f0-9]{128}\z/, secret)
      assert_equal 0o600, File.stat("#{work}/app/.env.local-clone-secret").mode & 0o777
      _, error, status = Open3.capture3(environment.merge("DOCKER_HOST" => "ssh://production"),
        "#{work}/app/bin/local-clone", "start")
      refute status.success?
      assert_includes error, "remote Docker contexts are refused"
    end
  end
end
