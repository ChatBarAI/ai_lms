require "test_helper"

class AvatarsHelperTest < ActionView::TestCase
  include ImageVariantsHelper

  test "uploaded avatar wins and is served as a variant" do
    user = users(:student)
    user.image_url = "https://example.com/provider.png"
    user.avatar.attach(fixture_file_upload("poster.png", "image/png"))
    user.save!

    html = user_avatar_tag(user, size_class: "w-7 h-7", initial_class: "text-xs")

    assert_includes html, "/rails/active_storage/"
    assert_includes html, "w-7 h-7 rounded-full"
    assert_not_includes html, "example.com"
  end

  test "falls back to the provider image" do
    user = users(:student)
    user.image_url = "https://example.com/provider.png"

    html = user_avatar_tag(user, size_class: "w-20 h-20", initial_class: "text-2xl")

    assert_includes html, %(src="https://example.com/provider.png")
    assert_includes html, "w-20 h-20 rounded-full"
  end

  test "falls back to the first letter of the display name" do
    user = users(:student)
    user.image_url = nil
    user.name = "zoe"

    html = user_avatar_tag(user, size_class: "w-20 h-20", initial_class: "text-2xl")

    assert_match %r{<div class="w-20 h-20 text-2xl [^"]*">Z</div>}, html
  end
end
