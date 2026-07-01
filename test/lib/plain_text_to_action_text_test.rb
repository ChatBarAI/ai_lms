require "test_helper"

class PlainTextToActionTextTest < ActiveSupport::TestCase
  test "html_for returns empty string for blank input" do
    assert_equal "", PlainTextToActionText.html_for(nil)
    assert_equal "", PlainTextToActionText.html_for("")
  end

  test "html_for wraps plain text in paragraphs" do
    html = PlainTextToActionText.html_for("Hello world")
    assert_equal "<p>Hello world</p>", html
  end

  test "html_for escapes HTML and preserves line breaks within paragraphs" do
    html = PlainTextToActionText.html_for("Line one\nLine two")
    assert_equal "<p>Line one<br>Line two</p>", html
  end

  test "html_for splits double newlines into separate paragraphs" do
    html = PlainTextToActionText.html_for("First block\n\nSecond block")
    assert_equal "<p>First block</p><p>Second block</p>", html
  end

  test "html_for escapes angle brackets" do
    html = PlainTextToActionText.html_for("<script>alert(1)</script>")
    assert_equal "<p>&lt;script&gt;alert(1)&lt;/script&gt;</p>", html
  end
end
