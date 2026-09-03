require "test_helper"

class SafeHtmlPolicyTest < ActiveSupport::TestCase
  test "allows only supplied video asset URLs in AI documents" do
    allowed = "/material-design-assets/video/file"
    html = <<~HTML
      <html><body>
        <video controls preload="metadata" aria-label="Worked example">
          <source src="#{allowed}" type="video/mp4">
          <source src="https://example.com/tracker.mp4" type="video/mp4">
        </video>
        <video src="https://example.com/untrusted.mp4" controls></video>
      </body></html>
    HTML

    sanitized = SafeHtmlPolicy.sanitize_ai_document(html, video_urls: [ allowed ])

    assert_includes sanitized, "<video"
    assert_includes sanitized, %(src="#{allowed}")
    assert_includes sanitized, %(aria-label="Worked example")
    assert_not_includes sanitized, "tracker.mp4"
    assert_not_includes sanitized, "untrusted.mp4"
  end

  test "does not enable videos in ordinary isolated HTML" do
    sanitized = SafeHtmlPolicy.sanitize_isolated_document(
      '<html><body><video controls src="/unapproved.mp4"></video></body></html>'
    )

    assert_not_includes sanitized, "<video"
    assert_not_includes sanitized, "unapproved.mp4"
  end

  test "preserves safe semantic layout elements in isolated documents" do
    html = <<~HTML
      <html><head><style>header { color: navy; }</style></head><body>
        <header><nav>Menu</nav></header>
        <main><section><article>Lesson</article></section><aside>Note</aside></main>
        <footer>Footer</footer>
      </body></html>
    HTML

    sanitized = SafeHtmlPolicy.sanitize_isolated_document(html)

    %w[header nav main section article aside footer].each do |tag|
      assert_includes sanitized, "<#{tag}>"
    end
  end
end
