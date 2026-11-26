require "test_helper"

class CertificateTimeZoneTest < ActiveSupport::TestCase
  test "certificate date uses the recipient zone regardless of the viewer or job zone" do
    user = User.new(time_zone: "Asia/Singapore")
    certificate = Certificate.new(user: user, issued_at: Time.utc(2026, 11, 25, 20))
    Time.use_zone("America/New_York") do
      assert_equal Date.new(2026, 11, 26), certificate.issued_on
    end
    Time.use_zone("UTC") do
      assert_equal Date.new(2026, 11, 26), certificate.issued_on
    end
  end
end
