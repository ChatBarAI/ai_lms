# frozen_string_literal: true

require "net/smtp"
require "openssl"
require "timeout"
require "resolv"
require "socket"

class EmailDiagnostics
  PROVIDERS = { "SendGrid" => "smtp.sendgrid.net", "Mailjet" => "in-v3.mailjet.com" }.freeze
  DIRECT_DOMAINS = %w[gmail.com outlook.com].freeze

  def initialize(smtp:, method:, sender:, app_url:, sendmail:, timeout: 8,
    host: nil, ports: nil, providers: false, recipient_domain: nil, output: $stdout)
    @smtp, @method, @sender, @app_url, @sendmail = smtp, method, sender, app_url, sendmail
    @timeout, @host, @ports, @output = timeout, host || smtp[:address], ports, output
    @providers = providers
    @host_override = host
    @endpoint_results = {}
    @direct_domains = recipient_domain ? [ recipient_domain ] : DIRECT_DOMAINS
  end

  def run
    say "Delivery method: #{@method}"
    say "Sender: #{present?(@sender) ? 'configured' : 'MISSING (set MAILER_SENDER)'}"
    say "Public URL: #{present?(@app_url) ? 'configured' : 'MISSING (set APP_HOST for email links)'}"
    if private_relay?(@smtp[:address], 25)
      say "Private Docker relay: SMTP credentials and a sendmail executable in the Rails container are not required."
    else
      say "SMTP username: #{present?(@smtp[:user_name]) ? 'configured' : 'not set'}; password: #{present?(@smtp[:password]) ? 'configured' : 'not set'}"
    end
    local_available = present?(@sendmail) && File.file?(@sendmail) && File.executable?(@sendmail)
    say "Local sendmail executable: #{local_available ? 'available' : 'not found'}"
    say "This executable check applies only to local sendmail delivery, not a separate SMTP container."

    result = check_selected_host
    direct_ok = check_direct

    if @providers
      say "Checking external providers; these are connectivity candidates, not configured accounts."
      results = PROVIDERS.map do |name, host|
        say "\nProvider: #{name}"
        check_host(host, @ports || [ 587, 465 ])
      end
      configured_summary
      return 2 if result == 2
      return result == 0 || results.include?(0) || direct_ok ? 0 : 1
    end

    configured_summary
    result == 1 && direct_ok ? 0 : result
  end

  private

  def check_selected_host
    unless @method.to_s == "smtp" || @host_override
      say "Configured delivery uses #{@method}; SMTP settings are not the active transport."
      return 1
    end

    if !present?(@host) || %w[localhost 127.0.0.1 ::1 [::1]].include?(@host.to_s.downcase)
      say "For external provider connectivity, re-run with --providers (or --host YOUR_PROVIDER_SMTP_HOST)."
    end

    unless present?(@host)
      say "No SMTP host configured. Re-run with --host YOUR_PROVIDER_SMTP_HOST to check ports 587 and 465."
      return 1
    end
    say "\n#{@host_override ? 'Requested' : 'Configured'} SMTP connection:"
    if @providers
      return check_host(@host, [ Integer(@smtp[:port] || 587) ], configured: true)
    end
    defaults = private_relay?(@host, 25) ? [ 25 ] : [ Integer(@smtp[:port] || 587), 587, 465 ].uniq
    check_host(@host, @ports || defaults, configured: !@host_override)
  end

  def configured_summary
    say "\nConfigured email system summary:"
    if @method.to_s != "smtp"
      say "Active transport: #{@method}. SMTP probes do not verify this transport's delivery."
    else
      port = Integer(@smtp[:port] || 587)
      status = @endpoint_results[[ @smtp[:address], port ]]
      if status
        say "Configured SMTP endpoint is reachable#{private_relay?(@smtp[:address], port) ? ' (Docker mail relay)' : ''}."
      elsif status == false
        say "Configured SMTP endpoint could not be reached/negotiated successfully. Working alternatives do not fix this configuration."
      else
        say "Configured SMTP endpoint was not checked (missing settings or overridden host/ports)."
      end
    end
    say "Connectivity only: this run did not send mail or verify relay authorization, credentials, or inbox placement."
  end

  def check_direct
    say "\nDirect delivery: resolving recipient MX servers and checking SMTP greetings on port 25."
    results = @direct_domains.map do |domain|
      begin
        hosts = direct_hosts(domain)
        if hosts.empty?
          say "#{domain}: null MX; domain does not accept email."
          next false
        end
        # Bound runtime: sample the two highest-priority MX servers per domain.
        hosts.first(2).map do |host|
          result = direct_probe(host)
          say "#{domain} -> #{host}:25: #{result}"
          result == "OK (SMTP greeting received)"
        end.any?
      rescue Resolv::ResolvError, SocketError, Timeout::Error
        say "#{domain}: MX lookup failed or timed out."
        false
      end
    end
    reachable = results.any?
    say(reachable ? "Direct SMTP connectivity is available to at least one sampled destination." :
      "No direct SMTP route verified; DNS failures, recipient policies or outbound port-25 restrictions may be responsible.")
    say "Direct probes check outbound connectivity, independently of your configured mail system; they do not verify DNS authentication or recipient acceptance."
    say "In Docker, sendmail is checked only inside this container. A host MTA must be reachable from the container; do not configure a recipient MX as the app's relay."
    say "No authentication or email delivery attempted; settings unchanged.\n"
    reachable
  end

  def direct_hosts(domain)
    Timeout.timeout(@timeout) do
      Resolv::DNS.open do |dns|
        dns.timeouts = @timeout
        records = dns.getresources(domain, Resolv::DNS::Resource::IN::MX)
        # RFC 7505 null MX means no mail; no MX uses the domain's address records.
        return [] if records.any? { |record| record.exchange.to_s.delete_suffix(".").empty? }
        records.empty? ? [ domain ] : records.sort_by(&:preference).map { |record| record.exchange.to_s }.uniq
      end
    end
  end

  def direct_probe(host, port = 25)
    socket = nil
    Timeout.timeout(@timeout) do
      socket = Socket.tcp(host, port, connect_timeout: @timeout)
      # Read a bounded SMTP greeting only: no AUTH, MAIL FROM, RCPT TO or DATA.
      20.times do
        line = socket.gets(513)
        return "invalid/rejected SMTP greeting" unless line && line.bytesize <= 512 && line.match?(/\A220[- ]/)
        return "OK (SMTP greeting received)" if line.start_with?("220 ")
      end
      "invalid/rejected SMTP greeting"
    end
  rescue SocketError
    "DNS resolution failed"
  rescue Timeout::Error
    "timed out"
  rescue SystemCallError, IOError => e
    "connection failed (#{e.class})"
  ensure
    socket&.close
  end

  def check_host(host, ports, configured: false)
    # Only accept a hostname/IP, not a URL, userinfo, or shell configuration.
    unless host.match?(/\A[a-zA-Z0-9.:\[\]-]+\z/)
      say "Invalid SMTP host; supply a hostname or IP address."
      return 2
    end

    raise ArgumentError unless ports.all? { |p| p.between?(1, 65_535) }
    modes = {}
    working = ports.select do |port|
      active_endpoint = configured && port == Integer(@smtp[:port] || 587)
      mode = active_endpoint ? configured_tls_mode : (port == 465 ? :tls : :starttls)
      modes[port] = mode
      if mode == :plaintext
        result = port == 25 ? direct_probe(host) : direct_probe(host, port)
        success = result == "OK (SMTP greeting received)"
      else
        result = probe(host, port, mode: mode)
        success = result == "OK"
      end
      labels = { tls: "implicit TLS", starttls: "required STARTTLS", starttls_auto: "opportunistic STARTTLS", plaintext: "configured plaintext relay" }
      say "#{host}:#{port} (#{labels.fetch(mode)}): #{result}"
      @endpoint_results[[ host, port ]] = success if active_endpoint
      success
    end

    if working.include?(25) && private_relay?(host, 25)
      say "Configured private relay is reachable. Relay authorization, queue processing and recipient delivery remain unverified."
      return 0
    end

    if working.empty?
      say "No SMTP endpoint passed these connection checks. Check DNS, outbound firewall rules, provider host and ports."
      say "A failure here does not prove a cloud-wide port block. If SMTP is unavailable, an HTTPS mail API requires an app integration."
      return 1
    end

    port = working.include?(587) ? 587 : working.first
    say "\nCandidate environment settings (apply manually, or enter in Admin > Site settings > Integration):"
    say "MAIL_DELIVERY_METHOD=smtp"
    say "SMTP_ADDRESS=#{host}"
    say "SMTP_PORT=#{port}"
    say "SMTP_ENABLE_STARTTLS_AUTO=#{[ :starttls, :starttls_auto ].include?(modes[port])}"
    say "SMTP_SSL=#{modes[port] == :tls}"
    say "SMTP_TLS=false"
    say "SMTP_OPENSSL_VERIFY_MODE=peer"
    say "Set SMTP_USERNAME, SMTP_PASSWORD and SMTP_AUTHENTICATION from your provider; set MAILER_SENDER and APP_HOST."
    say "Saved Admin overrides take precedence. Restart app/worker processes after environment changes."
    say "Connection check only: credentials, sender-domain DNS authentication and inbox delivery remain unverified."
    say "No credentials were sent, no email was sent, and no settings were changed."
    0
  end

  def private_relay?(host, port)
    host == "mail" && host == @smtp[:address] && port == 25 &&
      @smtp[:port].to_i == 25 && @smtp[:enable_starttls_auto] == false && !@smtp[:ssl] && !@smtp[:tls]
  end

  def configured_tls_mode
    return :tls if @smtp[:ssl] || @smtp[:tls]
    return :starttls if @smtp[:enable_starttls]
    return :plaintext if @smtp[:enable_starttls_auto] == false

    :starttls_auto
  end

  def probe(host, port, mode: port == 465 ? :tls : :starttls)
    Timeout.timeout(@timeout) do
      smtp = Net::SMTP.new(host, port)
      smtp.open_timeout = @timeout
      smtp.read_timeout = @timeout
      context = OpenSSL::SSL::SSLContext.new
      context.set_params(verify_mode: OpenSSL::SSL::VERIFY_PEER)
      context.verify_hostname = true
      case mode
      when :tls then smtp.enable_tls(context)
      when :starttls_auto then smtp.enable_starttls_auto(context)
      else smtp.enable_starttls(context)
      end
      # Intentionally omit credentials: connect, EHLO, verify TLS, then QUIT.
      smtp.start("diagnostic.invalid") { }
    end
    "OK"
  rescue OpenSSL::SSL::SSLError
    "TLS verification/handshake failed"
  rescue SocketError
    "DNS resolution failed"
  rescue Timeout::Error
    "timed out"
  rescue SystemCallError, IOError, Net::SMTPError => e
    "connection/SMTP negotiation failed (#{e.class})"
  end

  def present?(value)
    !value.to_s.strip.empty?
  end

  def say(message)
    @output.puts(message)
  end
end
