require "test_helper"

class SafeHtmlPolicyTest < ActiveSupport::TestCase
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
