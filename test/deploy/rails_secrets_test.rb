# Standalone: ruby test/deploy/rails_secrets_test.rb (no Rails, database or SSH).
require "minitest/autorun"
require "open3"
require "tmpdir"

class RailsSecretsTest < Minitest::Test
  HELPER = File.expand_path("../../deploy/lib/rails-secrets.sh", __dir__)

  def write_secrets(key = "")
    Open3.capture3("bash", "-eu", "-c", 'source "$1"; lms_write_rails_secrets "$2"', "test", HELPER, key)
  end

  def test_independent_installs_receive_distinct_signing_secrets
    first, err, status = write_secrets
    assert status.success?, err
    assert_match(/\ASECRET_KEY_BASE=[a-f0-9]{128}\n\z/, first)
    second, err, status = write_secrets
    assert status.success?, err
    assert_match(/\ASECRET_KEY_BASE=[a-f0-9]{128}\n\z/, second)
    refute_equal first, second
  end

  def test_explicit_key_is_preserved_without_overriding_secret_key_base
    Dir.mktmpdir do |dir|
      path = File.join(dir, "production.key")
      File.write(path, "#{'ab' * 16}\r\n")
      out, err, status = write_secrets(path)
      assert status.success?, err
      assert_equal "RAILS_MASTER_KEY=#{'ab' * 16}\n", out
    end
  end

  def test_invalid_explicit_key_fails_instead_of_generating_a_secret
    Dir.mktmpdir do |dir|
      path = File.join(dir, "production.key")
      [ nil, "", "invalid-key" ].each do |contents|
        File.write(path, contents) if contents
        out, _, status = write_secrets(path)
        refute status.success?
        assert_empty out
      end
    end
  end

  def test_server_preserves_existing_secrets_and_only_initializes_new_instances
    server = File.read(File.expand_path("../../deploy/server", __dir__))
    creation = server[/if \[\[ ! -f \$env_file \]\]; then\n  postgres_password=.*?^else$/m]
    refute_nil creation
    creation = creation.sub(/else\z/, "fi")
    Dir.mktmpdir do |dir|
      env_file = File.join(dir, ".env")
      script = 'source "$1"; env_file=$2; rails_key_file=; app_domain=example.com; requested_domains=; ' + creation
      _, err, status = Open3.capture3("bash", "-eu", "-c", script, "test", HELPER, env_file)
      assert status.success?, err
      generated = File.read(env_file)
      assert_match(/^SECRET_KEY_BASE=[a-f0-9]{128}$/, generated)
      refute_includes generated, "RAILS_MASTER_KEY="
      assert_equal 0o600, File.stat(env_file).mode & 0o777

      [ generated, "RAILS_MASTER_KEY=#{'ab' * 16}\n" ].each do |saved|
        File.write(env_file, saved)
        _, err, status = Open3.capture3("bash", "-eu", "-c", script, "test", HELPER, env_file)
        assert status.success?, err
        assert_equal saved, File.read(env_file)
      end
    end
  end
end
