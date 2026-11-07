# Runs without Rails or PostgreSQL; safe to load in the full Rails suite.
require "minitest/autorun"
require "open3"
require "rbconfig"

class EmailHostInventoryTest < Minitest::Test
  def test_standalone_checks_in_isolation
    script = File.expand_path("../support/mail_checks/email_host_check.rb", __dir__)
    output, error, status = Open3.capture3(RbConfig.ruby, script)
    assert status.success?, "#{output}\n#{error}"
  end
end
