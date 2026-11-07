# Configure the private outbound relay, then run Postfix in the foreground.
require "ipaddr"

module DockerMail
  def self.configuration(env)
    hostname = env.fetch("MAIL_HOSTNAME", "")
    labels = hostname.split(".", -1)
    unless hostname.length <= 253 && labels.length >= 2 && labels.all? { |label| label.match?(/\A[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\z/) }
      raise ArgumentError, "MAIL_HOSTNAME must be a fully qualified DNS hostname"
    end

    cidr = env.fetch("MAIL_NETWORK", "172.30.25.0/24")
    network = IPAddr.new(cidr)
    private_ranges = %w[10.0.0.0/8 172.16.0.0/12 192.168.0.0/16].map { |value| IPAddr.new(value) }
    unless network.ipv4? && network.prefix >= 24 && private_ranges.any? { |range| range.include?(network) } &&
        IPAddr.new(cidr.split("/").first) == network
      raise ArgumentError, "MAIL_NETWORK must be an RFC1918 IPv4 network /24 or smaller with no host bits set"
    end

    {
      "myhostname" => hostname,
      "myorigin" => hostname,
      "inet_interfaces" => "all",
      "inet_protocols" => "ipv4",
      "mynetworks" => "127.0.0.0/8, #{network}/#{network.prefix}",
      "mydestination" => "",
      "relay_domains" => "",
      "relayhost" => "",
      "smtpd_relay_restrictions" => "permit_mynetworks, reject_unauth_destination",
      "smtpd_client_restrictions" => "permit_mynetworks, reject",
      "smtpd_sasl_auth_enable" => "no",
      "smtpd_tls_security_level" => "none",
      "smtp_tls_security_level" => "may",
      "smtp_tls_CAfile" => "/etc/ssl/certs/ca-certificates.crt",
      "maillog_file" => "/dev/stdout",
      "message_size_limit" => "26214400",
      "disable_vrfy_command" => "yes"
    }
  end

  def self.start!
    configuration(ENV).each do |name, value|
      system("postconf", "-e", "#{name} = #{value}", exception: true)
    end
    # Postfix's postlog service provides stdout logging without a syslog daemon.
    system("postconf", "-M", "postlog/unix-dgram=postlog unix-dgram n - n - 1 postlogd", exception: true)
    system("postfix", "set-permissions", exception: true)
    system("postfix", "check", exception: true)
    exec("postfix", "start-fg")
  end
end

DockerMail.start! if $PROGRAM_NAME == __FILE__
