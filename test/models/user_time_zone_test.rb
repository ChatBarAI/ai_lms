require "test_helper"

class UserTimeZoneTest < ActiveSupport::TestCase
  test "manual zone takes priority over the detected zone with UTC fallback" do
    user = User.new
    assert_equal "UTC", user.effective_time_zone
    user.browser_time_zone = "Asia/Singapore"
    assert_equal "Asia/Singapore", user.effective_time_zone
    user.time_zone = "Europe/Berlin"
    assert_equal "Europe/Berlin", user.effective_time_zone
    user.time_zone = "invalid"
    assert_equal "Asia/Singapore", user.effective_time_zone
  end

  test "named zones apply daylight saving to each timestamp" do
    user = User.new(time_zone: "Europe/Berlin")
    Time.use_zone(user.effective_time_zone) do
      assert_equal "13:00 +01:00", Time.utc(2026, 1, 15, 12).in_time_zone.strftime("%H:%M %:z")
      assert_equal "14:00 +02:00", Time.utc(2026, 7, 15, 12).in_time_zone.strftime("%H:%M %:z")
    end
  end

  test "invalid profile timezone is rejected" do
    user = users(:student)
    user.time_zone = "invalid"
    assert_not user.valid?
    assert user.errors[:time_zone].any?
  end
end
