# Subprocess-only fixture; launched by test/deploy/email_host_check_test.rb.
# Standalone: ruby test/deploy/email_host_check_test.rb (no Rails or network).
require "tmpdir"
require "open3"

def assert(condition, message)
  raise message unless condition
end

script = File.expand_path("../../../lib/email_host_check.sh", __dir__)
Dir.mktmpdir("mail-inventory-test") do |dir|
  commands = {
    "dpkg-query" => 'case "$*" in *postfix) printf "install ok installed" ;; *) exit 1 ;; esac',
    "postfix" => 'echo "DAEMON MUST NOT BE RUN"; exit 99',
    "ps" => 'printf "master\nqmgr\nother\n"',
    "ss" => 'printf "LISTEN 0 100 127.0.0.1:25 0.0.0.0:*\nLISTEN 0 100 [::]:587 [::]:*\nLISTEN 0 100 0.0.0.0:80 0.0.0.0:*\n"',
    "systemctl" => 'printf "LoadState=loaded\nActiveState=active\nSubState=running\n"'
  }
  commands.each do |name, body|
    path = File.join(dir, name)
    File.write(path, "#!/bin/sh\n#{body}\n")
    File.chmod(0o755, path)
  end
  env = { "PATH" => "#{dir}:#{ENV.fetch('PATH')}" }
  out, err, status = Open3.capture3(env, "sh", script, "test host")
  assert(status.success?, err)
  assert(out.include?("Mail server inventory (test host)"), "Label execution scope")
  assert(out.include?("postfix: package=yes; executable=found"), "Find installed Postfix without running it")
  assert(!out.include?("DAEMON MUST NOT BE RUN"), "Never execute daemon binaries")
  assert(out.include?("exim4: package=not found in dpkg"), "Distinguish absent package")
  assert(out.include?("  master") && out.include?("  qmgr"), "Report process-name evidence")
  assert(out.include?("127.0.0.1:25") && out.include?("[::]:587") && !out.include?(":80"), "Filter listening mail ports")
  File.write(File.join(dir, "ss"), "#!/bin/sh\nexit 1\n")
  File.write(File.join(dir, "ps"), "#!/bin/sh\nprintf 'other\\n'\n")
  out, _, status = Open3.capture3(env, "sh", script)
  assert(status.success? && out.include?("ss missing or permission denied") && out.include?("none detected"), "Report unavailable tools without aborting checks")
end
puts "Mail host inventory tests passed."
