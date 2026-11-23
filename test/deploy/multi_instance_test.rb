# Standalone: ruby test/deploy/multi_instance_test.rb (no Rails, Docker or SSH).
require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require "yaml"

class MultiInstanceDeploymentTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  LIB = "#{ROOT}/deploy/lib/instance.sh"

  def lib(script, env = {})
    out, err, status = Open3.capture3(env, "bash", "-c", "set -Eeuo pipefail; source #{LIB}; #{script}")
    assert status.success?, err
    out
  end

  def test_default_instance_keeps_single_instance_names
    assert_equal "ai_lms\n/opt/ai_lms\nlms-default-web\n",
      lib("lms_instance_project default; lms_instance_root default; lms_edge_upstream default")
  end

  def test_named_instances_get_their_own_names
    assert_equal "ai_lms_acme\n/opt/ai_lms/instances/acme\nlms-acme-web\n",
      lib("lms_instance_project acme; lms_instance_root acme; lms_edge_upstream acme")
  end

  def test_instance_name_rules
    %w[default acme a acme-2 x123].each { |name| lib("lms_valid_instance #{name}") }
    [ "Acme", "a_b", "-a", "a-", "edge", "../a", "a b", "", "x" * 31 ].each do |name|
      _, _, status = Open3.capture3("bash", "-c", "source #{LIB}; lms_valid_instance \"$1\"", "_", name)
      refute status.success?, name.inspect
    end
  end

  def test_scripts_default_to_the_deployment_they_run_from
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p("#{dir}/instances/acme/releases/abc/deploy")
      FileUtils.mkdir_p("#{dir}/instances/acme/shared")
      FileUtils.touch("#{dir}/instances/acme/shared/.env")
      assert_equal "#{dir}/instances/acme\n", lib("lms_default_deploy_root #{dir}/instances/acme/releases/abc")
      assert_equal "/opt/ai_lms\n", lib("lms_default_deploy_root #{dir}/checkout")
    end
  end

  def test_env_without_instance_belongs_to_default_instance
    Dir.mktmpdir do |dir|
      File.write("#{dir}/.env", "APP_DOMAIN=a.example.com\n")
      assert_equal "default\n", lib("lms_env_instance #{dir}/.env")
      lib("lms_env_set #{dir}/.env INSTANCE acme; lms_env_set #{dir}/.env INSTANCE beta")
      assert_equal "APP_DOMAIN=a.example.com\nINSTANCE=beta\n", File.read("#{dir}/.env")
    end
  end

  def test_mail_network_allocation_avoids_docker_networks_and_other_instances
    Dir.mktmpdir do |dir|
      File.write("#{dir}/docker", <<~'SH')
        #!/usr/bin/env bash
        case "$1" in
          network)
            if [[ $2 == ls ]]; then echo n1; echo n2; else printf '172.17.0.0/16\n172.30.26.0/24\n'; fi ;;
        esac
      SH
      File.chmod(0o755, "#{dir}/docker")
      FileUtils.mkdir_p("#{dir}/base/instances/other/shared")
      File.write("#{dir}/base/instances/other/shared/.env", "MAIL_NETWORK=172.30.27.0/24\n")
      out = lib("LMS_BASE_ROOT=#{dir}/base; lms_allocate_mail_network", "PATH" => "#{dir}:#{ENV.fetch('PATH')}")
      assert_equal "172.30.28.0/24\n", out
    end
  end

  def test_mail_network_allocation_detects_overlapping_wider_networks
    Dir.mktmpdir do |dir|
      File.write("#{dir}/docker", <<~'SH')
        #!/usr/bin/env bash
        [[ $2 == ls ]] && echo n1 || echo 172.30.0.0/16
      SH
      File.chmod(0o755, "#{dir}/docker")
      _, err, status = Open3.capture3({ "PATH" => "#{dir}:#{ENV.fetch('PATH')}" }, "bash", "-c",
        "source #{LIB}; LMS_BASE_ROOT=#{dir}; lms_allocate_mail_network")
      refute status.success?
      assert_includes err, "No free"
    end
  end

  def render_site(env_contents, instance: "acme")
    server = File.read("#{ROOT}/deploy/server")
    function = server[/^render_site\(\) \{\n.*?^\}\n/m]
    refute_nil function
    Dir.mktmpdir do |dir|
      File.write("#{dir}/.env", env_contents)
      script = "set -Eeuo pipefail; source #{LIB}; #{function}\nrender_site"
      env = { "env_file" => "#{dir}/.env", "instance" => instance, "app_domain" => "fallback.example.com",
        "edge_upstream" => "lms-#{instance}-web" }
      out, err, status = Open3.capture3(env, "bash", "-c", script)
      return [ out, err, status ]
    end
  end

  def test_site_file_routes_all_domains_to_the_instance
    out, err, status = render_site("APP_DOMAINS=learn.acme.com, academy.acme.com\nACME_EMAIL=admin@acme.com\n")
    assert status.success?, err
    assert_includes out, "learn.acme.com, academy.acme.com {\n"
    assert_includes out, "\ttls admin@acme.com\n"
    assert_includes out, "\treverse_proxy lms-acme-web:3000\n"
    assert_includes out, "max_size 110MB"
  end

  def test_site_file_lists_repeated_domains_once
    out, err, status = render_site("APP_DOMAINS=ai-academy-staging.chatbar-ai.com, ai-academy-staging.chatbar-ai.com\n")
    assert status.success?, err
    assert_includes out, "\nai-academy-staging.chatbar-ai.com {\n"
  end

  def test_site_file_rejects_unsafe_domains_and_skips_unsafe_email
    _, _, status = render_site("APP_DOMAINS=a.example.com, evil.com {\n")
    refute status.success?
    out, err, status = render_site("APP_DOMAINS=a.example.com\nACME_EMAIL=x@y.com }\n")
    assert status.success?, err
    refute_includes out, "tls"
  end

  def test_instance_stack_has_no_public_ports_and_prefixed_volumes
    config = YAML.load_file("#{ROOT}/compose.yaml", aliases: true)
    services = config.fetch("services")
    refute services.key?("proxy")
    services.each_value { |service| refute service.key?("ports") }
    assert_equal "${COMPOSE_PROJECT_NAME:-ai_lms}", config.fetch("name")
    config.fetch("volumes").each do |key, volume|
      assert_equal "${COMPOSE_PROJECT_NAME:-ai_lms}_#{key}", volume.fetch("name")
    end
    assert_equal({ "name" => "ai_lms_edge", "external" => true }, config.dig("networks", "edge"))
    assert_equal [ "${EDGE_UPSTREAM:-lms-default-web}" ], services.dig("web", "networks", "edge", "aliases")
    refute services.fetch("worker").fetch("networks").include?("edge")
    mail = YAML.load_file("#{ROOT}/compose.mail.yaml")
    assert_equal "${COMPOSE_PROJECT_NAME:-ai_lms}_mail_queue", mail.dig("volumes", "mail_queue", "name")
  end

  def test_edge_stack_owns_public_ports_and_reuses_certificates
    edge = YAML.load_file("#{ROOT}/deploy/edge/compose.yaml")
    assert_equal "ai_lms_edge", edge.fetch("name")
    caddy = edge.dig("services", "caddy")
    assert_equal [ "80:80", "443:443", "443:443/udp" ], caddy.fetch("ports")
    assert_includes caddy.fetch("volumes"), "./caddy:/etc/caddy:ro"
    assert_equal({ "name" => "ai_lms_caddy_data", "external" => true }, edge.dig("volumes", "caddy_data"))
    assert_includes File.read("#{ROOT}/deploy/edge/Caddyfile"), "import sites/*.caddy"
  end

  # Runs deploy/server's real exit handler against a temporary layout.
  def run_exit_handler(root, status:, first_deploy:, services_started: false, extra: "")
    server = File.read("#{ROOT}/deploy/server")
    functions = %w[undo_first_deploy on_exit].map { |name| server[/^#{name}\(\) \{\n.*?^\}\n/m] }
    functions.each { |function| refute_nil function }
    script = <<~SH
      #{functions.join("\n")}
      instance=acme deploy_root=#{root} shared_dir=#{root}/shared env_file=#{root}/shared/.env
      release_dir=#{root}/releases/abc rails_key_file= remove_key=false
      first_deploy=#{first_deploy} services_started=#{services_started}
      #{extra}
      trap on_exit EXIT
      exit #{status}
    SH
    Open3.capture3("bash", "-c", script)
  end

  def first_deploy_layout(root)
    FileUtils.mkdir_p([ "#{root}/shared", "#{root}/releases/abc/deploy", "#{root}/.edge-stage/sites" ])
    File.write("#{root}/shared/.env", "INSTANCE=acme\n")
    FileUtils.touch("#{root}/.deploy.lock")
  end

  def test_failed_first_deploy_before_services_leaves_nothing_behind
    Dir.mktmpdir do |dir|
      root = "#{dir}/instances/acme"
      first_deploy_layout(root)
      _, err, status = run_exit_handler(root, status: 1, first_deploy: true)
      assert_equal 1, status.exitstatus
      assert_includes err, "removing the files it created"
      refute File.exist?(root)
      assert File.directory?("#{dir}/instances")
    end
  end

  def test_failed_first_deploy_keeps_unrelated_files_in_the_root
    Dir.mktmpdir do |dir|
      first_deploy_layout(dir)
      FileUtils.mkdir_p([ "#{dir}/instances/other", "#{dir}/edge/caddy" ])
      run_exit_handler(dir, status: 1, first_deploy: true)
      assert File.directory?("#{dir}/instances/other")
      assert File.directory?("#{dir}/edge/caddy")
      refute File.exist?("#{dir}/shared")
      refute File.exist?("#{dir}/releases")
    end
  end

  def test_exit_handler_keeps_files_after_success_later_deploys_or_started_services
    [ { status: 0, first_deploy: true }, { status: 1, first_deploy: false },
      { status: 1, first_deploy: true, services_started: true } ].each do |options|
      Dir.mktmpdir do |dir|
        first_deploy_layout(dir)
        _, _, status = run_exit_handler(dir, **options)
        assert_equal options[:status], status.exitstatus
        assert File.exist?("#{dir}/shared/.env"), options.inspect
        assert File.directory?("#{dir}/releases/abc"), options.inspect
      end
    end
  end

  def test_exit_handler_always_removes_the_uploaded_rails_key
    Dir.mktmpdir do |dir|
      first_deploy_layout(dir)
      File.write("#{dir}/production.key", "key")
      run_exit_handler(dir, status: 0, first_deploy: false,
        extra: "rails_key_file=#{dir}/production.key remove_key=true")
      refute File.exist?("#{dir}/production.key")
    end
  end

  def test_server_validates_edge_before_changing_the_app_and_publishes_after_health
    server = File.read("#{ROOT}/deploy/server")
    order = [ "flock -n 9", "first_deploy=true", 'lms_env_set "$env_file" INSTANCE', 'validate_edge_config "$edge_stage"',
      '"${compose[@]}" build web', "services_started=true", "up -d --wait --wait-timeout 150 db redis",
      "Web container did not become healthy",
      'validate_edge_config "$edge_root/caddy"', 'docker rm -f "${legacy_proxies[@]}"',
      "caddy reload", 'check-readiness" https', "ln -sfn" ]
    order.each { |marker| assert_includes server, marker }
    order.each_cons(2) { |a, b| assert_operator server.index(a), :<, server.index(b), "#{a} before #{b}" }
    refute_match(/up -d[^\n]*proxy/, server)
  end
end
