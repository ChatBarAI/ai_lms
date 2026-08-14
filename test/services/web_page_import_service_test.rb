require "test_helper"

class WebPageImportServiceTest < ActiveSupport::TestCase
  class FakeFetcher
    attr_reader :requests

    def initialize(responses)
      @responses = responses
      @requests = []
    end

    def fetch(url, **options)
      @requests << [ url, options ]
      @responses.fetch(url)
    end
  end

  class FailingResourceFetcher
    attr_reader :requests

    def initialize(page)
      @page = page
      @requests = []
    end

    def fetch(url, **options)
      @requests << [ url, options ]
      return @page if @requests.one?

      raise SecureHttpFetcher::Error, "missing resource"
    end
  end

  test "imports a page with same-origin CSS and images" do
    image_bytes = Rails.root.join("test/fixtures/files/poster.png").binread
    responses = {
      "https://example.com/page" => result(
        "https://example.com/page",
        "text/html",
        <<~HTML
          <!doctype html>
          <html>
            <head>
              <title>Remote lesson</title>
              <link rel="stylesheet" href="/site.css">
            </head>
            <body class="remote-page">
              <script>alert("no")</script>
              <div class="card">Article</div>
              <img src="/hero.png">
              <img src="https://cdn.example.com/tracker.png">
              <a href="/more">Read more</a>
            </body>
          </html>
        HTML
      ),
      "https://example.com/site.css" => result(
        "https://example.com/site.css",
        "text/css",
        ".card { font-family: Roboto; background-image: url('/background.png'); }"
      ),
      "https://example.com/hero.png" => result("https://example.com/hero.png", "image/png", image_bytes),
      "https://example.com/background.png" => result("https://example.com/background.png", "image/png", image_bytes)
    }
    fetcher = FakeFetcher.new(responses)
    material = LessonMaterial.new(
      lesson: lessons(:intro),
      title: "",
      kind: :web_page,
      url: "https://example.com/page"
    )

    WebPageImportService.new(material: material, fetcher: fetcher).call

    assert material.persisted?
    assert_equal "Remote lesson", material.title
    assert_equal 2, material.imported_assets.count
    assert_includes material.raw_html_content, 'class="remote-page"'
    assert_includes material.raw_html_content, 'font-family:"Roboto", system-ui'
    assert_includes material.raw_html_content, "rails/active_storage"
    assert_includes material.raw_html_content, 'href="https://example.com/more"'
    assert_not_includes material.raw_html_content, "<script"
    assert_not_includes material.raw_html_content, "cdn.example.com"
  end

  test "failed resource requests count toward the resource limit" do
    images = 150.times.map { |index| %(<img src="/missing-#{index}.png">) }.join
    page = result(
      "https://example.com/page",
      "text/html",
      "<!doctype html><html><body>#{images}</body></html>"
    )
    fetcher = FailingResourceFetcher.new(page)
    material = LessonMaterial.new(
      lesson: lessons(:intro),
      title: "Remote page",
      kind: :web_page,
      url: "https://example.com/page"
    )

    error = assert_raises(WebPageImportService::ImportError) do
      WebPageImportService.new(material: material, fetcher: fetcher).call
    end

    assert_equal "The page contains too many resources.", error.message
    assert_equal WebPageImportService::MAX_RESOURCES, fetcher.requests.size
  end

  private

  def result(url, content_type, body)
    SecureHttpFetcher::Result.new(body: body, content_type: content_type, uri: URI(url))
  end
end
