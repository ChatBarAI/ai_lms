# Run without Rails or PostgreSQL: ruby test/lib/email_diagnostics_check.rb
require "stringio"
require_relative "../../lib/email_diagnostics"

def assert(condition, message)
  raise message unless condition
end

def build_diagnostic(**options)
  check = EmailDiagnostics.new(**options)
  check.define_singleton_method(:check_direct) { false }
  check
end

def diagnostic(host: "smtp.example.com", results: {}, ports: nil)
  output = StringIO.new
  check = build_diagnostic(smtp: { address: host, user_name: "SECRET_USER", password: "SECRET_PASSWORD" },
    method: "smtp", sender: "sender@example.com", app_url: "example.com",
    sendmail: "/nonexistent/sendmail", ports: ports, output: output)
  check.define_singleton_method(:probe) { |_host, port, **_options| results.fetch(port, "timed out") }
  [ check.run, output.string ]
end

status, output = diagnostic(results: { 587 => "OK", 465 => "OK" })
assert(status == 0 && output.include?("SMTP_PORT=587"), "Prefer working STARTTLS port")
assert(!output.include?("SECRET"), "Never expose credentials")
status, output = diagnostic(results: { 465 => "OK" })
assert(status == 0 && output.include?("SMTP_SSL=true") && output.include?("SMTP_ENABLE_STARTTLS_AUTO=false"), "Suggest implicit TLS for 465")
status, output = diagnostic
assert(status == 1 && !output.include?("MAIL_DELIVERY_METHOD=smtp"), "Do not recommend failed endpoints")
status, = diagnostic(host: nil)
assert(status == 1, "Missing host needs operator input")
status, = diagnostic(host: "user:secret@example.com")
assert(status == 2, "Reject userinfo in host")

# Exercise the real probe setup without opening network connections.
fake = Object.new
class << fake
  attr_accessor :open_timeout, :read_timeout, :mode
  def enable_starttls(context)
    raise "TLS verification disabled" unless context.verify_mode == OpenSSL::SSL::VERIFY_PEER && context.verify_hostname
    self.mode = :starttls
  end
  def enable_tls(context)
    enable_starttls(context)
    self.mode = :tls
  end
  def enable_starttls_auto(context)
    enable_starttls(context)
    self.mode = :starttls_auto
  end
  def start(*args)
    raise "Credentials passed to SMTP" unless args == [ "diagnostic.invalid" ]
    yield
  end
end
original_new = Net::SMTP.method(:new)
begin
  Net::SMTP.define_singleton_method(:new) { |*_args| fake }
  check = build_diagnostic(smtp: {}, method: "smtp", sender: nil, app_url: nil, sendmail: nil)
  assert(check.send(:probe, "example.com", 587) == "OK" && fake.mode == :starttls, "Require STARTTLS")
  assert(check.send(:probe, "example.com", 465) == "OK" && fake.mode == :tls, "Use implicit TLS")
  assert(check.send(:probe, "example.com", 2525, mode: :tls) == "OK" && fake.mode == :tls, "Support implicit TLS on nonstandard ports")
  assert(check.send(:probe, "example.com", 465, mode: :starttls_auto) == "OK" && fake.mode == :starttls_auto, "Honor opportunistic STARTTLS even on port 465")
  fake.define_singleton_method(:start) { |*_args| raise OpenSSL::SSL::SSLError, "SECRET" }
  assert(check.send(:probe, "example.com", 587) == "TLS verification/handshake failed", "Handle TLS failures without leaking details")
ensure
  Net::SMTP.define_singleton_method(:new, original_new)
end
output = StringIO.new
calls = []
check = build_diagnostic(smtp: { address: "localhost", port: 25 }, method: "smtp",
  sender: nil, app_url: nil, sendmail: nil, providers: true, output: output)
check.define_singleton_method(:probe) do |host, port, **_options|
  calls << [ host, port ]
  host == "in-v3.mailjet.com" && port == 465 ? "OK" : "timed out"
end
assert(check.run == 0, "One reachable provider is sufficient")
assert(calls == [ [ "localhost", 25 ] ] + EmailDiagnostics::PROVIDERS.values.product([ 587, 465 ]), "Probe configured endpoint first, then all providers")
assert(output.string.include?("SMTP_ADDRESS=in-v3.mailjet.com") && !output.string.include?("SMTP_ADDRESS=smtp.sendgrid.net"), "Only suggest reachable providers")
check.define_singleton_method(:probe) { |*_args| "timed out" }
assert(check.run == 1, "All failed providers return failure")
output = StringIO.new
check = build_diagnostic(smtp: {}, method: "smtp", sender: nil, app_url: nil,
  sendmail: nil, providers: true, ports: [ 587 ], output: output)
calls = []
check.define_singleton_method(:probe) { |host, port, **_options| calls << [ host, port ]; "OK" }
assert(check.run == 0 && calls.all? { |_, port| port == 587 }, "Honor custom provider ports without a configured host")
puts "Email diagnostic checks passed."

# Default direct checks run even with no configured SMTP host.
output = StringIO.new
check = EmailDiagnostics.new(smtp: {}, method: "sendmail", sender: nil, app_url: nil,
  sendmail: nil, output: output)
domains = []
check.define_singleton_method(:direct_hosts) { |domain| domains << domain; [ "mx.#{domain}" ] }
check.define_singleton_method(:direct_probe) { |_host| "OK (SMTP greeting received)" }
assert(check.run == 0 && domains == EmailDiagnostics::DIRECT_DOMAINS, "Direct test is enabled by default without SMTP configuration")
assert(!output.string.include?("SMTP_ADDRESS=mx."), "Do not recommend recipient MX as relay")
check.define_singleton_method(:direct_hosts) { |_domain| raise Resolv::ResolvError }
assert(check.run == 1, "Report failed DNS without aborting")
check.define_singleton_method(:direct_hosts) { |_domain| [] }
assert(check.run == 1, "Null MX is not a working route")

check = EmailDiagnostics.new(smtp: {}, method: "smtp", sender: nil, app_url: nil,
  sendmail: nil, recipient_domain: "example.com", output: StringIO.new)
domains = []
hosts = []
check.define_singleton_method(:direct_hosts) { |domain| domains << domain; %w[mx1 mx2 mx3] }
check.define_singleton_method(:direct_probe) { |host| hosts << host; "timed out" }
assert(check.run == 1 && domains == [ "example.com" ] && hosts == %w[mx1 mx2], "Override domain and bound MX sampling")

# Greeting-only probe: no SMTP commands or credentials are written.
check = EmailDiagnostics.new(smtp: {}, method: "smtp", sender: nil, app_url: nil, sendmail: nil)
original_tcp = Socket.method(:tcp)
begin
  [ [ "220-test\r\n220 Ready\r\n", true ], [ "554 Rejected\r\n", false ],
    [ "", false ], [ "220 " + "x" * 600, false ] ].each do |greeting, success|
    socket = StringIO.new(greeting)
    Socket.define_singleton_method(:tcp) do |_host, port, **_opts|
      raise "Wrong port" unless port == 25
      socket
    end
    result = check.send(:direct_probe, "mx.example.com")
    assert(result.start_with?("OK") == success && socket.closed?, "Validate greeting and close connection")
    assert(socket.string == greeting, "Probe must not write commands")
  end
ensure
  Socket.define_singleton_method(:tcp, original_tcp)
end
puts "Default direct-delivery checks passed."

original_dns_open = Resolv::DNS.method(:open)
resolver = Object.new
resolver.define_singleton_method(:timeouts=) { |_value| }
records = []
resolver.define_singleton_method(:getresources) { |*_args| records }
begin
  Resolv::DNS.define_singleton_method(:open) { |&block| block.call(resolver) }
  assert(check.send(:direct_hosts, "example.com") == [ "example.com" ], "No MX uses domain fallback")
  records = [ Resolv::DNS::Resource::IN::MX.new(0, Resolv::DNS::Name.create(".")) ]
  assert(check.send(:direct_hosts, "example.com").empty?, "Null MX disables fallback")
  records = [ [ 20, "mx2.example.com" ], [ 10, "mx1.example.com" ] ].map do |priority, host|
    Resolv::DNS::Resource::IN::MX.new(priority, Resolv::DNS::Name.create(host))
  end
  assert(check.send(:direct_hosts, "example.com") == %w[mx1.example.com mx2.example.com], "Sort MX records by preference")
ensure
  Resolv::DNS.define_singleton_method(:open, original_dns_open)
end
puts "MX resolution checks passed."

output = StringIO.new
check = build_diagnostic(smtp: { address: "mail", port: 25, enable_starttls_auto: false },
  method: "smtp", sender: nil, app_url: nil, sendmail: nil, output: output)
check.define_singleton_method(:direct_probe) { |host| raise "Wrong relay" unless host == "mail"; "OK (SMTP greeting received)" }
check.define_singleton_method(:probe) { |*_args| raise "Private plaintext relay must not require TLS" }
assert(check.run == 0 && output.string.include?("Configured private relay is reachable"), "Diagnose Docker relay without TLS")
puts "Docker relay diagnostic checks passed."

# --providers must not bypass the configured Docker relay or imply that missing
# executables/credentials mean it is broken.
output = StringIO.new
calls = []
check = build_diagnostic(smtp: { address: "mail", port: 25, enable_starttls_auto: false },
  method: "smtp", sender: nil, app_url: nil, sendmail: nil, providers: true, output: output)
check.define_singleton_method(:direct_probe) { |host| calls << host; "OK (SMTP greeting received)" }
check.define_singleton_method(:probe) { |host, port, **_options| calls << [ host, port ]; "timed out" }
assert(check.run == 0 && calls.first == "mail", "Provider mode checks active relay first")
assert(output.string.include?("Configured SMTP endpoint is reachable (Docker mail relay)"), "Report active relay success even when providers fail")
assert(output.string.include?("not required") && !output.string.include?("password: missing"), "Explain optional credentials and local executable")

output.truncate(0)
output.rewind
check.define_singleton_method(:direct_probe) { |_host| "connection failed" }
check.define_singleton_method(:probe) { |*_args| "OK" }
assert(check.run == 0, "Reachable alternatives preserve discovery exit semantics")
assert(output.string.include?("Configured SMTP endpoint could not be reached"), "Provider success must not conceal configured relay failure")
assert(!output.string.include?("Configured SMTP endpoint is reachable"), "Do not claim the configured relay works")
puts "Provider-mode configured relay checks passed."

[
  [ { ssl: true }, :tls ],
  [ { tls: true }, :tls ],
  [ { enable_starttls_auto: true }, :starttls_auto ],
  [ { enable_starttls: true }, :starttls ],
  [ { enable_starttls_auto: false }, :plaintext ]
].each do |settings, expected_mode|
  output = StringIO.new
  calls = []
  check = build_diagnostic(smtp: { address: "custom.example.com", port: 2525 }.merge(settings),
    method: "smtp", sender: nil, app_url: nil, sendmail: nil, providers: true, output: output)
  check.define_singleton_method(:probe) { |host, port, mode:| calls << [ host, port, mode ]; "OK" }
  check.define_singleton_method(:direct_probe) { |host, port| calls << [ host, port, :plaintext ]; "OK (SMTP greeting received)" }
  assert(check.run == 0, "Custom configured transport succeeds")
  assert(calls.first == [ "custom.example.com", 2525, expected_mode ], "Configured endpoint must honor #{expected_mode}")
  assert(calls.drop(1).all? { |_, port, mode| mode == (port == 465 ? :tls : :starttls) }, "Provider alternatives use their own TLS defaults")
end

# A provider discovery probe may use a different TLS mode at the same endpoint;
# it must not replace the result obtained with the actual saved settings.
output = StringIO.new
check = build_diagnostic(smtp: { address: "smtp.sendgrid.net", port: 587, enable_starttls_auto: false },
  method: "smtp", sender: nil, app_url: nil, sendmail: nil, providers: true, output: output)
check.define_singleton_method(:direct_probe) { |*_args| "connection failed" }
check.define_singleton_method(:probe) { |*_args, **_opts| "OK" }
check.run
assert(output.string.include?("Configured SMTP endpoint could not be reached"), "Alternative probe must not overwrite configured-mode failure")
puts "Configured TLS mode checks passed."
