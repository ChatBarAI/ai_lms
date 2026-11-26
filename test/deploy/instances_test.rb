# Standalone: ruby test/deploy/instances_test.rb (no Rails, Docker or SSH).
require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require "json"
require "digest"

class InstancesCommandTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  COMMIT = "660a6448b46fae8a32f8914189bd5de0ee0f8fed".freeze
  HEALTHY = {
    "ai_lms" => %w[web db redis], "ai_lms_test" => %w[web db redis], "ai_lms_edge" => %w[caddy]
  }.freeze

  def setup
    @work = Dir.mktmpdir
    @base = "#{@work}/opt"
    FileUtils.mkdir_p([ "#{@work}/bin", "#{@base}/edge/caddy/sites" ])
    File.write("#{@work}/bin/ssh", "#!/usr/bin/env bash\nexec bash -s\n")
    File.chmod(0o755, "#{@work}/bin/ssh")
    @containers = []
    @memory = {}
    @mem_total_kb = 4 * 1024 * 1024
    @mem_available_kb = 2 * 1024 * 1024
    @disk_size = 40 * 1024**3
    @disk_free = 30 * 1024**3
    @key_file = "#{@work}/production.key"
    File.write(@key_file, "ab" * 16)
  end

  def teardown
    FileUtils.remove_entry(@work)
  end

  def add_instance(name, root, env: "APP_DOMAINS=#{name}.example.com\n", site: true, release: true)
    FileUtils.mkdir_p("#{root}/shared")
    File.write("#{root}/shared/.env", env) if env
    if release
      FileUtils.mkdir_p("#{root}/releases/#{COMMIT}")
      File.symlink("#{root}/releases/#{COMMIT}", "#{root}/current")
    end
    FileUtils.touch("#{@base}/edge/caddy/sites/#{name}.caddy") if site
  end

  def container(project, service, state = "running", status = nil)
    status ||= HEALTHY.fetch(project, []).include?(service) ? "Up 5 minutes (healthy)" : "Up 5 minutes"
    @containers << [ project, service, state, status ].join("\t")
  end

  def healthy_stack(project)
    %w[web worker db redis].each { |service| container(project, service) }
  end

  def run_instances(*args)
    stats = @containers.filter_map do |c|
      project, service, state = c.split("\t")
      "'#{project}-#{service}-1\t#{@memory.fetch(project, 100)}MiB / 3.8GiB'" if state == "running"
    end
    File.write("#{@work}/bin/docker", <<~SH)
      #!/usr/bin/env bash
      case "$1" in
        ps) printf '%s\\n' #{@containers.map { |c| "'#{c}'" }.join(' ')} ;;
        stats) printf '%s\\n' #{stats.join(' ')} ;;
        info) echo /nonexistent ;;
      esac
    SH
    File.chmod(0o755, "#{@work}/bin/docker")
    File.write("#{@work}/meminfo", "MemTotal: #{@mem_total_kb} kB\nMemAvailable: #{@mem_available_kb} kB\nSwapTotal: 0 kB\nSwapFree: 0 kB\n")
    File.write("#{@work}/bin/df", <<~SH)
      #!/usr/bin/env bash
      echo 'Filesystem 1-blocks Used Available Capacity Mounted'
      echo '/dev/vda1 #{@disk_size} #{@disk_size - @disk_free} #{@disk_free} 50% /'
    SH
    File.chmod(0o755, "#{@work}/bin/df")
    env = { "PATH" => "#{@work}/bin:#{ENV.fetch('PATH')}", "LMS_BASE_ROOT" => @base, "NO_COLOR" => "1",
            "LMS_MEMINFO" => "#{@work}/meminfo", "RAILS_PRODUCTION_KEY_FILE" => @key_file }
    Open3.capture3(env, "#{ROOT}/bin/instances", *args, "root@203.0.113.10")
  end

  def test_healthy_server_lists_each_instance_once_without_secrets
    add_instance("default", @base, env: "APP_DOMAINS=a.example.com, a.example.com\nRAILS_MASTER_KEY=topsecret\n")
    add_instance("test", "#{@base}/instances/test")
    healthy_stack("ai_lms")
    healthy_stack("ai_lms_test")
    container("ai_lms_edge", "caddy")
    out, err, status = run_instances
    assert status.success?, out + err
    assert_includes out, "2 instances · edge proxy healthy"
    assert_includes out, "● default    a.example.com\n"
    assert_equal 1, out.scan("a.example.com").size
    assert_includes out, "● test       test.example.com"
    assert_includes out, "660a644 · deployed"
    assert_includes out, "No problems found."
    refute_includes out, "topsecret"
    assert_match(/Server    \d+ CPUs? · load /, out)
    assert_includes out, "Memory    2.0 GiB used of 4.0 GiB · 2.0 GiB available"
    assert_includes out, "Disk      30.0 GiB free of 40.0 GiB (25% used)"
    # Four running services at 100 MiB each.
    assert_includes out, "Memory    400.0 MiB"
  end

  def test_memory_usage_units_and_per_instance_totals
    add_instance("default", @base)
    healthy_stack("ai_lms")
    container("ai_lms_edge", "caddy")
    @memory["ai_lms"] = 1.5
    out, err, status = run_instances("--json")
    assert status.success?, err
    data = JSON.parse(out)
    assert_equal (4 * 1.5 * 1024**2).round, data.dig("instances", 0, "memory_bytes")
    assert data.dig("host", "memory", "total").positive?
    assert_equal "/", data.dig("host", "disks", 0, "path")
  end

  def test_reports_failed_first_deploy_orphan_site_and_stopped_service
    add_instance("default", @base)
    add_instance("dup", "#{@base}/instances/dup", env: nil, site: false, release: false)
    FileUtils.touch("#{@base}/edge/caddy/sites/old.caddy")
    healthy_stack("ai_lms")
    @containers.reject! { |c| c.start_with?("ai_lms\tworker") }
    container("ai_lms", "worker", "exited", "Exited (1) 2 minutes ago")
    container("ai_lms_edge", "caddy")
    container("ai_lms_gone", "web")
    out, _, status = run_instances
    assert_equal 1, status.exitstatus
    assert_includes out, "dup: no shared/.env"
    assert_includes out, "sites/old.caddy has no matching instance"
    assert_includes out, "default: worker is exited"
    assert_includes out, "containers for ai_lms_gone have no instance folder"
  end

  def test_server_not_yet_upgraded_is_not_reported_as_missing_edge
    add_instance("default", @base, site: false)
    healthy_stack("ai_lms")
    container("ai_lms", "proxy")
    out, = run_instances
    assert_includes out, "no edge proxy (not yet upgraded)"
    refute_includes out, "edge proxy container (ai_lms_edge-caddy-1) is missing"
    assert_includes out, "still runs its own proxy container"
  end

  def test_memory_above_two_gib_is_not_clamped
    add_instance("default", @base)
    healthy_stack("ai_lms")
    container("ai_lms_edge", "caddy")
    # The staging server's real figures; older mawk clamped these to 2 GiB.
    @mem_total_kb = 32_761_928
    @mem_available_kb = 29_987_284
    out, err, status = run_instances
    assert status.success?, err
    assert_includes out, "Memory    2.6 GiB used of 31.2 GiB · 28.6 GiB available"
  end

  def test_low_disk_and_memory_are_problems
    add_instance("default", @base)
    healthy_stack("ai_lms")
    container("ai_lms_edge", "caddy")
    @disk_free = 1 * 1024**3
    @mem_available_kb = 200 * 1024
    out, _, status = run_instances
    assert_equal 1, status.exitstatus
    assert_includes out, "low disk space on /: 1.0 GiB free of 40.0 GiB"
    assert_includes out, "low memory: 200.0 MiB available of 4.0 GiB"
  end

  def test_json_output
    add_instance("default", @base)
    healthy_stack("ai_lms")
    container("ai_lms_edge", "caddy")
    out, err, status = run_instances("--json")
    assert status.success?, err
    data = JSON.parse(out)
    assert_equal [ "default" ], data.fetch("instances").map { |i| i.fetch("name") }
    assert_equal [ "default.example.com" ], data.dig("instances", 0, "domains")
    assert_empty data.fetch("problems")
  end

  def test_master_key_comparison_and_generated_secret_modes_do_not_leak_secrets
    local = "ab" * 16
    other = "cd" * 16
    signing = "ef" * 64
    File.write(@key_file, "#{local}\r\n")
    add_instance("default", @base, env: "RAILS_MASTER_KEY=#{local}\n")
    add_instance("other", "#{@base}/instances/other", env: "RAILS_MASTER_KEY=#{other}\n")
    add_instance("independent", "#{@base}/instances/independent", env: "SECRET_KEY_BASE=#{signing}\n")
    %w[ai_lms ai_lms_other ai_lms_independent].each { |project| healthy_stack(project) }
    container("ai_lms_edge", "caddy")

    out, err, status = run_instances("--json")
    assert status.success?, err
    instances = JSON.parse(out).fetch("instances").to_h { |i| [ i.fetch("name"), i ] }
    assert_equal "match", instances.dig("default", "local_master_key_match")
    assert_equal "different", instances.dig("other", "local_master_key_match")
    assert_equal "secret_key_base", instances.dig("independent", "rails_secret_mode")
    assert_equal "not_applicable", instances.dig("independent", "local_master_key_match")
    [ local, other, signing, Digest::SHA256.hexdigest(local) ].each { |secret| refute_includes out + err, secret }

    out, err, status = run_instances
    assert status.success?, err
    assert_includes out, "master key: matches local key"
    assert_includes out, "master key: differs from local key"
    assert_includes out, "SECRET_KEY_BASE only (no master key)"
    [ local, other, signing ].each { |secret| refute_includes out + err, secret }
  end

  def test_missing_local_key_is_reported_without_claiming_a_mismatch
    File.delete(@key_file)
    # Use the default relative path from a directory without a production key.
    @key_file = nil
    add_instance("default", @base, env: "RAILS_MASTER_KEY=#{'ab' * 16}\n")
    healthy_stack("ai_lms")
    container("ai_lms_edge", "caddy")
    out, err, status = Dir.chdir(@work) { run_instances("--json") }
    assert status.success?, err
    assert_equal "no_local_key", JSON.parse(out).dig("instances", 0, "local_master_key_match")
  end

  def test_invalid_local_key_is_rejected_without_printing_it
    File.write(@key_file, "invalid-secret")
    out, err, status = run_instances
    assert_equal 2, status.exitstatus
    assert_includes err, "Local production key is missing or invalid"
    refute_includes out + err, "invalid-secret"
  end

  def test_invalid_target_does_not_connect
    _, _, status = Open3.capture3("#{ROOT}/bin/instances", "-oProxyCommand=bad")
    assert_equal 2, status.exitstatus
  end
end
