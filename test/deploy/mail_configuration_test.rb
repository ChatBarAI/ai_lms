# Standalone: ruby test/deploy/mail_configuration_test.rb; no Rails or network.
require "minitest/autorun"
require_relative "../../deploy/mail/entrypoint"

class DockerMailConfigurationTest < Minitest::Test
  def test_only_private_network_is_trusted
    config = DockerMail.configuration("MAIL_HOSTNAME" => "learn.example.com")
    assert_equal "127.0.0.0/8, 172.30.25.0/24", config["mynetworks"]
    assert_equal "permit_mynetworks, reject_unauth_destination", config["smtpd_relay_restrictions"]
    assert_equal "permit_mynetworks, reject", config["smtpd_client_restrictions"]
    %w[mydestination relay_domains relayhost].each { |key| assert_equal "", config[key] }
    assert_equal "may", config["smtp_tls_security_level"]
    assert_equal "none", config["smtpd_tls_security_level"]
  end

  def test_rejects_invalid_networks
    %w[0.0.0.0/0 10.0.0.0/8 8.8.8.0/24 ::/0 invalid 172.30.25.1/24].each do |network|
      assert_raises(ArgumentError) { DockerMail.configuration("MAIL_HOSTNAME" => "mail.example.com", "MAIL_NETWORK" => network) }
    end
  end

  def test_rejects_invalid_hostnames
    [ "", "localhost", "mail.example.com\nrelayhost=evil", "bad;name.example.com", "mail.example.com." ].each do |hostname|
      assert_raises(ArgumentError) { DockerMail.configuration("MAIL_HOSTNAME" => hostname) }
    end
  end

  def test_custom_hostname_and_network
    config = DockerMail.configuration("MAIL_HOSTNAME" => "mail.example.com", "MAIL_NETWORK" => "10.55.0.0/28")
    assert_equal "mail.example.com", config["myhostname"]
    assert_equal "127.0.0.0/8, 10.55.0.0/28", config["mynetworks"]
  end
end
