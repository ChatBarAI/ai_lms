# Isolate the standalone checks and their protocol mocks from Rails tests.
require "minitest/autorun"
require "open3"
require "rbconfig"

class EmailDiagnosticsTest < Minitest::Test
  def test_standalone_diagnostics
    output, error, status = Open3.capture3(RbConfig.ruby, File.expand_path("email_diagnostics_check.rb", __dir__))
    assert status.success?, "#{output}\n#{error}"
  end
end
