require "test_helper"

class SafeHtmlPolicyTest < ActiveSupport::TestCase
  test "preserves responsive inline styles in fragments and isolated documents" do
    styles = {
      "story" => "background:#FFFFFF;border:1px solid rgba(18,23,42,0.08);border-radius:20px;padding:clamp(28px,5vw,48px);box-shadow:0 8px 24px rgba(18,23,42,0.10);",
      "heading" => "font-size:clamp(38px,6.4vw,60px);text-transform:uppercase;",
      "section" => "padding:0 clamp(20px,6vw,32px) clamp(56px,9vw,96px);margin:clamp(32px,5vw,44px) auto 0;",
      "grid" => "display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:32px;",
      "sizing" => "box-sizing:border-box;width:min(100%,720px);max-width:calc((100% - 2rem) / 2);padding:max(1rem,2vw) !important;"
    }
    html = styles.map { |id, style| %(<div id="#{id}" style="#{style}">Content</div>) }.join

    [ :sanitize_fragment, :sanitize_isolated_document ].each do |method|
      document = Nokogiri::HTML5.parse(SafeHtmlPolicy.public_send(method, html))

      styles.each do |id, style|
        assert_equal style, document.at_css("##{id}")["style"], "#{method}: #{id}"
      end
    end
  end

  test "preserves responsive body styles and inline font fallbacks across repeated sanitization" do
    html = <<~HTML
      <html><body style="padding:clamp(20px,6vw,32px);font-family:Roboto;">
        <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:32px;">Content</div>
      </body></html>
    HTML

    sanitized = SafeHtmlPolicy.sanitize_isolated_document(html)
    body = Nokogiri::HTML5.parse(sanitized).at_css("body")

    assert_includes body["style"], "padding:clamp(20px,6vw,32px);"
    assert_includes body["style"], 'font-family:"Roboto", system-ui'
    resanitized = Nokogiri::HTML5.parse(SafeHtmlPolicy.sanitize_isolated_document(sanitized)).at_css("body")
    assert_equal body["style"], resanitized["style"]
    assert_equal body.at_css("div")["style"], resanitized.at_css("div")["style"]
  end

  test "rejects CSS URLs and executable values including escaped and nested functions" do
    unsafe_styles = [
      "background:url(https://tracker.example/pixel)",
      'background:u\\72l("https://tracker.example/pixel")',
      "background:linear-gradient(red, url(https://tracker.example/pixel))",
      'background:image-set("https://tracker.example/pixel" 1x)',
      "padding:clamp(1px, url(https://tracker.example/pixel), 4px)",
      "width:expression(alert(1))",
      'width:e\\78pression(alert(1))',
      "width:calc(100% - expression(alert(1)))",
      "width:var(--untrusted)",
      "behavior:url(https://tracker.example/behavior.htc)",
      "-moz-binding:url(https://tracker.example/binding.xml)",
      "position:fixed;z-index:9999",
      "--untrusted:url(https://tracker.example/pixel)"
    ]

    unsafe_styles.each do |style|
      assert_equal "color:red;", SafeHtmlPolicy.sanitize_inline_css("#{style};color:red;"), style
    end
  end

  test "custom style handling retains HTML safety checks in both modes" do
    html = <<~HTML
      <script>alert(1)</script><iframe src="https://tracker.example"></iframe>
      <form action="/users"><input name="admin"></form>
      <a href="javascript:alert(1)" onclick="alert(1)" style="padding:clamp(1px,2vw,3px);background:url(https://tracker.example/pixel)">Content</a>
    HTML

    [ :sanitize_fragment, :sanitize_isolated_document ].each do |method|
      document = Nokogiri::HTML5.parse(SafeHtmlPolicy.public_send(method, html))

      assert_empty document.css("script, iframe, form, input, [onclick], a[href]")
      assert_equal "padding:clamp(1px,2vw,3px);", document.at_css("a")["style"]
    end
  end

  test "does not expand the global Rails CSS allowlist" do
    style = "padding:clamp(28px,5vw,48px);box-shadow:0 8px 24px rgba(18,23,42,0.10);"
    sanitizer = Rails::HTML::SafeListSanitizer.new
    original = sanitizer.sanitize_css(style)

    SafeHtmlPolicy.sanitize_fragment(%(<div style="#{style}">Story</div>))

    assert_equal original, sanitizer.sanitize_css(style)
  end

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
