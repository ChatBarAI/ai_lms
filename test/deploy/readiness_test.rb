# Standalone: ruby test/deploy/readiness_test.rb (does not boot Rails).
require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"

class ReadinessTest < Minitest::Test
  SCRIPT = File.expand_path("../../deploy/check-readiness", __dir__)

  def setup
    @work = Dir.mktmpdir
    @env = { "PATH" => "#{@work}:#{ENV.fetch('PATH')}", "CALL_LOG" => "#{@work}/calls",
             "COUNTER" => "#{@work}/counter", "SSH_CONNECTION" => "" }
    stub("hostname", 'echo "85.93.90.221 2001:db8::1"')
    stub("dig", <<~'SH')
      echo "$*" >> "$CALL_LOG"
      [[ ${DNS_TIMEOUT:-0} == 0 ]] || exit 9
      echo ";; ->>HEADER<<- opcode: QUERY, status: ${DNS_STATUS:-NOERROR}, id: 1"
      if [[ $3 == A ]]; then
        address=${DNS_A-85.93.90.221}
      else
        address=${DNS_AAAA:-}
      fi
      if [[ -n $address ]]; then echo "$2. 300 IN $3 $address"; fi
    SH
    stub("curl", <<~'SH')
      printf '%q ' "$@" >> "$CALL_LOG"
      printf '\n' >> "$CALL_LOG"
      count=0
      [[ ! -f $COUNTER ]] || read -r count < "$COUNTER"
      count=$((count + 1))
      echo "$count" > "$COUNTER"
      if [[ ${CURL_MODE:-success} == retry && $count == 1 ]]; then
        echo 'TLS alert' >&2
        printf '\n000'
        exit 35
      fi
      if [[ ${CURL_MODE:-success} == fail ]]; then
        /bin/sleep 1
        echo 'certificate invalid' >&2
        printf '\n000'
        exit 60
      fi
      if [[ ${CURL_MODE:-success} == http_error ]]; then /bin/sleep 1; fi
      printf '\n%s' "${HTTP_CODE:-200}"
    SH
    stub("sleep", ":")
  end

  def teardown
    FileUtils.remove_entry(@work)
  end

  def stub(name, body)
    path = File.join(@work, name)
    File.write(path, "#!/usr/bin/env bash\nset -eu\n#{body}\n")
    File.chmod(0o755, path)
  end

  def check(mode, env = {}, domains = "learn.example.com")
    Open3.capture3(@env.merge(env), "bash", SCRIPT, mode, domains)
  end

  def test_ipv4_only_domains_aliases_and_both_resolvers
    out, err, status = check("dns", {}, "learn.example.com, alias.example.com, learn.example.com")
    assert status.success?, err
    assert_equal 2, out.lines.size
    calls = File.readlines(@env.fetch("CALL_LOG"))
    assert_equal 8, calls.size
    assert calls.any? { |line| line.include?("@8.8.8.8 alias.example.com AAAA") }
  end

  def test_dns_errors_missing_records_and_wrong_addresses
    [ { "DNS_STATUS" => "NXDOMAIN" }, { "DNS_TIMEOUT" => "1" }, { "DNS_A" => "" },
      { "DNS_A" => "192.0.2.2" }, { "DNS_AAAA" => "2001:db8::2" } ].each do |env|
      _, err, status = check("dns", env)
      refute status.success?, env.inspect
      assert_match(/DNS check failed|No public|outside this server/, err)
    end
  end

  def test_ipv6_normalization
    out, err, status = check("dns", { "DNS_AAAA" => "2001:0DB8:0:0:0:0:0:1" })
    assert status.success?, err
    assert_includes out, "DNS ready"
  end

  def test_ssh_server_address_is_accepted
    _, err, status = check("dns", { "DNS_A" => "192.0.2.2", "SSH_CONNECTION" => "192.0.2.1 1234 192.0.2.2 22" })
    assert status.success?, err
  end

  def test_normalizes_ipv6_edge_cases
    script = 'source "$1"; normalize_address "$2"'
    { "::" => "0000:" * 8,
      "::1" => "0000:" * 7 + "0001:",
      "2001:db8::" => "2001:0db8:" + "0000:" * 6,
      "::ffff:192.0.2.1" => "0000:" * 5 + "ffff:c000:0201:" }.each do |input, expected|
      out, err, status = Open3.capture3(@env, "bash", "-c", script, "bash", SCRIPT, input)
      assert status.success?, err
      assert_equal expected, out.strip
    end
  end

  def test_https_retries_and_checks_alias_without_bypassing_certificate_checks
    out, err, status = check("https", { "CURL_MODE" => "retry" }, "learn.example.com,alias.example.com")
    assert status.success?, err
    assert_includes out, "Waiting for HTTPS"
    assert_includes out, "HTTPS ready: https://alias.example.com"
    calls = File.readlines(@env.fetch("CALL_LOG"))
    assert_equal 3, calls.size
    calls.each do |call|
      assert_includes call, "--max-time"
      refute_match(/--insecure|--location/, call)
    end
  end

  def test_https_timeout_retains_diagnostic_and_rejects_redirects
    [ { "CURL_MODE" => "fail" },
      { "CURL_MODE" => "http_error", "HTTP_CODE" => "503" },
      { "CURL_MODE" => "http_error", "HTTP_CODE" => "302" } ].each do |env|
      script = 'source "$1"; domains=(learn.example.com); check_https 1'
      _, err, status = Open3.capture3(@env.merge(env), "bash", "-c", script, "bash", SCRIPT)
      refute status.success?
      assert_includes err, "HTTPS was not ready within 1 seconds"
      assert_match(/certificate invalid|HTTP 503|HTTP 302/, err)
    end
  end

  def test_empty_domains_are_rejected
    _, err, status = check("dns", {}, " , ")
    refute status.success?
    assert_includes err, "No deployment domains"
  end
end
