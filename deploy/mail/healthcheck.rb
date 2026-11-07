# Check SMTP readiness without authenticating or submitting mail.
require "net/smtp"
require "timeout"

module DockerMailHealthcheck
  def self.check!
    Timeout.timeout(3) do
      smtp = Net::SMTP.new("127.0.0.1", 25)
      smtp.open_timeout = 3
      smtp.read_timeout = 3
      smtp.disable_starttls
      smtp.start("healthcheck.invalid") { }
    end
  end
end

DockerMailHealthcheck.check! if $PROGRAM_NAME == __FILE__
