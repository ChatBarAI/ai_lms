# Subprocess-only fixture; launched by test/deploy/check_email_test.rb.
# Standalone: ruby test/deploy/check_email_test.rb (no Rails, Docker, or SSH connection).
require "tmpdir"
require "open3"
require "json"
require "shellwords"
require "rbconfig"

def assert(condition, message)
  raise message unless condition
end

script = File.expand_path("../../../bin/check-email", __dir__)
Dir.mktmpdir("check-email-test") do |dir|
  ssh = File.join(dir, "ssh")
  log = File.join(dir, "arguments.json")
  File.write(ssh, <<~RUBY)
    #!#{RbConfig.ruby}
    require "json"
    File.write(ENV.fetch("SSH_TEST_LOG"), JSON.generate(ARGV))
    File.write(ENV.fetch("SSH_TEST_LOG") + ".stdin", STDIN.read)
    exit Integer(ENV.fetch("SSH_TEST_STATUS", "0"))
  RUBY
  File.chmod(0o755, ssh)
  env = { "PATH" => "#{dir}:#{ENV.fetch('PATH')}", "SSH_TEST_LOG" => log, "SSH_PORT" => "2222" }
  args = [ RbConfig.ruby, script, "root@server.example.com", "--env-only",
    "--container", "ai_lms-worker-1", "--host", "smtp.example.com", "--ports", "587,465", "--timeout", "3" ]
  _, err, status = Open3.capture3(env, *args)
  assert(status.success?, "Remote dispatch failed: #{err}")
  ssh_args = JSON.parse(File.read(log))
  assert(ssh_args.first(2) == [ "-p", "2222" ], "Forward SSH_PORT")
  assert(ssh_args[-2] == "root@server.example.com", "Forward SSH target")
  assert(ssh_args.last == "sh -s", "Stream inventory in the same SSH session")
  payload = File.read(log + ".stdin")
  assert(payload.include?("systemctl show") && payload.include?("ss -H -ltn"), "Inspect remote host before container")
  remote = Shellwords.split(payload.lines.last).drop(1)
  assert(remote.first(9) == [ "docker", "exec", "-w", "/rails", "ai_lms-worker-1", "bundle", "exec", "ruby", "bin/check-email" ], "Run in app container")
  assert(remote.drop(9) == [ "--timeout", "3", "--env-only", "--host", "smtp.example.com", "--ports", "587,465" ], "Forward diagnostic options")
  [ 1, 2, 255 ].each do |code|
    _, _, status = Open3.capture3(env.merge("SSH_TEST_STATUS" => code.to_s), *args)
    assert(status.exitstatus == (code == 255 ? 2 : code), "Handle remote exit #{code}")
  end
  # SSH sends a shell command string; hostile option content must remain one argument.
  hostile = "smtp.example.com; touch /tmp/should-not-exist"
  Open3.capture3(env, RbConfig.ruby, script, "root@server.example.com", "--host", hostile)
  remote = Shellwords.split(File.read(log + ".stdin").lines.last).drop(1)
  assert(remote.last == hostile, "Shell-quote remote option values")
  _, _, status = Open3.capture3(env, RbConfig.ruby, script, "root@server.example.com", "--providers")
  remote = Shellwords.split(File.read(log + ".stdin").lines.last).drop(1)
  assert(status.success? && remote.include?("--providers"), "Forward provider discovery remotely")
  _, _, status = Open3.capture3(env, RbConfig.ruby, script, "root@server.example.com", "--recipient-domain", "example.com")
  remote = Shellwords.split(File.read(log + ".stdin").lines.last).drop(1)
  assert(status.success? && remote.last(2) == [ "--recipient-domain", "example.com" ], "Forward direct recipient domain")
  File.unlink(log)
  [ [ "-bad@host" ], [ "root@host;whoami" ], [ "root@host", "--container", "bad;name" ],
    [ "root@host", "--providers", "--host", "smtp.example.com" ],
    [ "root@host", "--recipient-domain", "bad;domain.com" ] ].each do |invalid|
    _, _, status = Open3.capture3(env, RbConfig.ruby, script, *invalid)
    assert(status.exitstatus == 2 && !File.exist?(log), "Reject invalid arguments before SSH")
  end
  _, _, status = Open3.capture3(env.merge("SSH_PORT" => "0"), *args)
  assert(status.exitstatus == 2 && !File.exist?(log), "Reject invalid SSH port")
end
puts "Remote email checker tests passed."
