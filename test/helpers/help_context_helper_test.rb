require "test_helper"

class HelpContextHelperTest < ActionView::TestCase
  tests HelpContextHelper

  setup do
    controller.request.path = "/admin/courses/1/edit"
  end

  test "includes role and path" do
    text = ask_help_context_string(namespace: "admin")
    assert_includes text, "Role: admin"
    assert_includes text, "Path: /admin/courses/1/edit"
  end

  test "includes course and lesson when assigned" do
    @course = courses(:algebra)
    @lesson = lessons(:intro)
    text = ask_help_context_string(namespace: "admin")
    assert_includes text, @course.title
    assert_includes text, @lesson.title
    assert_includes text, "id: #{@lesson.id}"
  end

  test "iframe url points at dashboard cbai show with context" do
    url = ask_help_iframe_url(token: "help-lms-admin", context: "Role: admin")
    assert_match %r{\Ahttps?://.+/cbais/help-lms-admin\?}, url
    assert_includes url, "additional_context="
    assert_includes url, CGI.escape("Role: admin")
  end
end
