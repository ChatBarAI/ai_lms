require "test_helper"

class HelpPageCodeAssemblerTest < ActiveSupport::TestCase
  test "loads admin manifest pages" do
    keys = Help::PageCodeAssembler.page_keys("admin")
    assert_includes keys, "courses_edit"
    assert_includes keys, "site_settings_integration"
  end

  test "extracts HELP comments into markdown" do
    config = Help::PageCodeAssembler.load_all_pages("admin").fetch("courses_edit")
    md = Help::PageCodeAssembler.new("courses_edit", config, namespace: "admin").to_markdown
    assert_includes md, "Course cover image"
    assert_includes md, "Upload a PNG, JPG, or WebP cover"
    assert_includes md, "app/views/courses/_fields.html.haml"
  end

  test "integration page HELP mentions Ask Us token" do
    config = Help::PageCodeAssembler.load_all_pages("admin").fetch("site_settings_integration")
    md = Help::PageCodeAssembler.new("site_settings_integration", config, namespace: "admin").to_markdown
    assert_includes md, "Ask Us help bot setup"
    assert_includes md, "paste the bot token"
  end
end
