# Standalone: ruby test/deploy/mail_healthcheck_test.rb; no Rails or network.
require "minitest/autorun"
require "minitest/mock"
require_relative "../../deploy/mail/healthcheck"

class DockerMailHealthcheckTest < Minitest::Test
  def test_checks_local_smtp_without_credentials_or_mail
    smtp = Minitest::Mock.new
    smtp.expect(:open_timeout=, 3, [ 3 ])
    smtp.expect(:read_timeout=, 3, [ 3 ])
    smtp.expect(:disable_starttls, nil)
    smtp.expect(:start, nil, [ "healthcheck.invalid" ])
    factory = ->(host, port) do
      assert_equal "127.0.0.1", host
      assert_equal 25, port
      smtp
    end
    Net::SMTP.stub(:new, factory) { DockerMailHealthcheck.check! }
    smtp.verify
  end

  def test_connection_failures_fail_the_healthcheck
    factory = ->(*_args) { raise Errno::ECONNREFUSED }
    Net::SMTP.stub(:new, factory) do
      assert_raises(Errno::ECONNREFUSED) { DockerMailHealthcheck.check! }
    end
  end
end
