require "securerandom"
require "stringio"
require "uri"

class WebPageImportService
  class ImportError < StandardError; end

  MAX_HTML_BYTES = 5.megabytes
  MAX_STYLESHEET_BYTES = 1.megabyte
  MAX_IMAGE_BYTES = 10.megabytes
  MAX_TOTAL_BYTES = 50.megabytes
  MAX_RESOURCES = 100

  HTML_CONTENT_TYPES = %w[text/html application/xhtml+xml].freeze
  CSS_CONTENT_TYPES = %w[text/css].freeze
  IMAGE_CONTENT_TYPES = %w[image/png image/jpeg image/gif image/webp].freeze
  IMAGE_EXTENSIONS = {
    "image/png" => ".png",
    "image/jpeg" => ".jpg",
    "image/gif" => ".gif",
    "image/webp" => ".webp"
  }.freeze

  def initialize(material:, fetcher: SecureHttpFetcher.new)
    @material = material
    @fetcher = fetcher
    @bytes_fetched = 0
    @resources_fetched = 0
    @asset_paths = {}
    @created_blobs = []
  end

  def call
    raise ImportError, "Enter a public HTTPS page URL." if material.url.blank?

    old_assets = material.imported_assets.to_a
    page = fetch(material.url, max_bytes: MAX_HTML_BYTES, content_types: HTML_CONTENT_TYPES)
    @page_uri = page.uri
    document = Nokogiri::HTML5.parse(page.body)
    material.title = inferred_title(document, page.uri) if material.title.blank?

    styles = collect_styles(document, page.uri)
    rewrite_images!(document, page.uri)
    rewrite_links!(document, page.uri)
    document.css("script, form, iframe, object, embed, base, link, style").remove

    material.raw_html_content = build_document(document, styles)
    material.save!
    old_assets.each(&:purge)
    material
  rescue SecureHttpFetcher::Error => error
    cleanup_created_blobs
    raise ImportError, error.message
  rescue ImportError
    cleanup_created_blobs
    raise
  rescue ActiveRecord::RecordInvalid
    cleanup_created_blobs
    raise
  end

  private

  attr_reader :material, :fetcher

  def fetch(url, max_bytes:, content_types:)
    raise ImportError, "The page contains too many resources." if @resources_fetched >= MAX_RESOURCES

    @resources_fetched += 1

    remaining = MAX_TOTAL_BYTES - @bytes_fetched
    raise ImportError, "The imported page exceeds the 50 MB total limit." if remaining <= 0

    result = fetcher.fetch(
      url,
      max_bytes: [ max_bytes, remaining ].min,
      allowed_content_types: content_types,
      allowed_origin: @page_uri
    )
    @bytes_fetched += result.body.bytesize
    result
  end

  def collect_styles(document, page_uri)
    styles = document.css("style").map { |node| process_css(node.text, page_uri) }

    document.css('link[rel~="stylesheet"][href]').each do |link|
      stylesheet_uri = same_origin_uri(link["href"], page_uri)
      next if stylesheet_uri.blank?

      begin
        stylesheet = fetch(stylesheet_uri.to_s, max_bytes: MAX_STYLESHEET_BYTES, content_types: CSS_CONTENT_TYPES)
        styles << process_css(stylesheet.body, stylesheet.uri)
      rescue SecureHttpFetcher::Error
        next
      end
    end

    styles.join("\n")
  end

  def process_css(css, base_uri)
    replacements = {}
    token_prefix = "LMS_ASSET_#{SecureRandom.hex(12)}"
    index = 0

    with_placeholders = css.to_s.gsub(/url\(\s*(['"]?)(.*?)\1\s*\)/i) do
      asset_uri = same_origin_uri(::Regexp.last_match(2), base_uri)
      asset_path = import_image(asset_uri)
      next "none" if asset_path.blank?

      token = "#{token_prefix}_#{index}"
      index += 1
      replacements[token] = %(url("#{asset_path}"))
      token
    end

    sanitized = SafeHtmlPolicy.sanitize_stylesheet(with_placeholders)
    replacements.each { |token, value| sanitized.gsub!(token, value) }
    sanitized
  end

  def rewrite_images!(document, page_uri)
    document.css("img").each do |image|
      source = image["src"].presence || image["data-src"].presence || first_srcset_url(image["srcset"])
      asset_path = import_image(same_origin_uri(source, page_uri))

      unless asset_path
        image.remove
        next
      end

      image["src"] = asset_path
      image.remove_attribute("srcset")
      image.remove_attribute("data-src")
      image["loading"] = "lazy"
    end
  end

  def rewrite_links!(document, page_uri)
    document.css("a[href]").each do |link|
      href = link["href"].to_s
      next if href.start_with?("#", "mailto:", "tel:")

      absolute = URI.join(page_uri, href)
      unless %w[http https].include?(absolute.scheme)
        link.remove_attribute("href")
        next
      end

      link["href"] = absolute.to_s
      link["target"] = "_blank"
      link["rel"] = "noopener noreferrer"
    rescue URI::InvalidURIError
      link.remove_attribute("href")
    end
  end

  def import_image(uri)
    return if uri.blank?
    return @asset_paths[uri.to_s] if @asset_paths.key?(uri.to_s)

    image = fetch(uri.to_s, max_bytes: MAX_IMAGE_BYTES, content_types: IMAGE_CONTENT_TYPES)
    verified_type = Marcel::MimeType.for(StringIO.new(image.body), name: File.basename(image.uri.path))
    raise ImportError, "An imported image did not match its declared file type." unless verified_type == image.content_type

    filename = File.basename(image.uri.path).presence || "web-image#{IMAGE_EXTENSIONS.fetch(verified_type)}"
    filename += IMAGE_EXTENSIONS.fetch(verified_type) if File.extname(filename).blank?
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(image.body),
      filename: filename,
      content_type: verified_type
    )
    @created_blobs << blob
    material.imported_assets.attach(blob)
    @asset_paths[uri.to_s] = Rails.application.routes.url_helpers.rails_storage_proxy_path(blob, disposition: "inline", only_path: true)
  rescue SecureHttpFetcher::Error, KeyError
    @asset_paths[uri.to_s] = nil
  end

  def same_origin_uri(value, base_uri)
    return if value.blank?
    return if value.to_s.strip.start_with?("#", "data:")

    uri = URI.join(base_uri, value.to_s.strip)
    return unless uri.scheme == "https"
    return unless uri.host&.casecmp?(base_uri.host)
    return unless uri.port == base_uri.port

    uri.fragment = nil
    uri
  rescue URI::InvalidURIError
    nil
  end

  def first_srcset_url(srcset)
    srcset.to_s.split(",").first.to_s.strip.split(/\s+/, 2).first
  end

  def build_document(document, styles)
    source_body = document.at_css("body")
    body = SafeHtmlPolicy.sanitize_fragment(source_body&.inner_html.to_s)

    <<~HTML
      <!doctype html>
      <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>#{styles}</style>
        </head>
        <body#{SafeHtmlPolicy.safe_body_attributes(source_body)}>#{body}</body>
      </html>
    HTML
  end

  def inferred_title(document, uri)
    document.at_css("title")&.text.to_s.squish.presence || uri.host
  end

  def cleanup_created_blobs
    @created_blobs.each(&:purge)
  end
end
