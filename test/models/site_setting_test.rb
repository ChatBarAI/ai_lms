require "test_helper"

class SiteSettingTest < ActiveSupport::TestCase
  test "current creates a record on first call" do
    SiteSetting.delete_all
    assert_difference -> { SiteSetting.count }, 1 do
      SiteSetting.current
    end
  end

  test "current is idempotent" do
    SiteSetting.current
    assert_no_difference -> { SiteSetting.count } do
      SiteSetting.current
    end
  end

  test "allow_guest_access defaults to true" do
    SiteSetting.delete_all
    assert SiteSetting.current.allow_guest_access?
  end

  test "logo rejects non-image content types" do
    s = SiteSetting.current
    s.logo.attach(io: StringIO.new("x"), filename: "x.txt", content_type: "text/plain")
    assert_not s.valid?
    assert s.errors[:logo].any?
  end
end
