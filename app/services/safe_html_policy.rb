require "cgi"

module SafeHtmlPolicy
  ALLOWED_TAGS = %w[
    p br strong b em i u s h1 h2 h3 h4 h5 h6 ul ol li blockquote code pre
    a img figure figcaption table colgroup col thead tbody tfoot tr th td
    div span hr sup sub header main section footer nav article aside address details summary
  ].freeze
  ALLOWED_ATTRIBUTES = %w[
    href src alt title class id style dir lang target rel name width height
    colspan rowspan span start type value scope headers
  ].freeze
  VIDEO_TAGS = %w[video source].freeze
  VIDEO_ATTRIBUTES = %w[aria-label controls preload playsinline muted loop].freeze

  SYSTEM_FONT_STACKS = {
    sans: 'system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", Arial, sans-serif',
    serif: 'Georgia, "Times New Roman", serif',
    condensed: '"Arial Narrow", Arial, sans-serif',
    mono: 'ui-monospace, "SFMono-Regular", Consolas, "Liberation Mono", monospace',
    handwriting: '"Comic Sans MS", "Bradley Hand", cursive'
  }.freeze
  FONT_MAPPINGS = {
    sans: %w[
      aptos calibri google-sans inter lato montserrat nunito open-sans poppins
      raleway roboto source-sans-3 source-sans-pro ubuntu work-sans pt-sans
      noto-sans
    ],
    serif: %w[
      cambria libre-baskerville lora merriweather noto-serif playfair-display
      pt-serif source-serif-3 source-serif-pro
    ],
    condensed: %w[oswald roboto-condensed],
    mono: %w[roboto-mono source-code-pro noto-sans-mono],
    handwriting: %w[caveat dancing-script pacifico]
  }.each_with_object({}) do |(category, names), mappings|
    names.each { |name| mappings[name.tr("-", " ")] = category }
  end.freeze

  module_function

  def sanitize_fragment(html, video_urls: [])
    source = Nokogiri::HTML5.fragment(html.to_s)
    source.css("script, style, form, iframe, object, embed").remove
    sanitized = Rails::HTML::SafeListSanitizer.new.sanitize(
      source.to_html,
      tags: ALLOWED_TAGS + (video_urls.any? ? VIDEO_TAGS : []),
      attributes: ALLOWED_ATTRIBUTES + (video_urls.any? ? VIDEO_ATTRIBUTES : [])
    )
    fragment = Nokogiri::HTML5.fragment(sanitized)
    restrict_video_sources(fragment, video_urls) if video_urls.any?
    map_inline_fonts(fragment)
    fragment.to_html
  end

  def sanitize_isolated_document(html, video_urls: [])
    return "" if html.blank?

    document = Nokogiri::HTML5.parse(html.to_s)
    source_body = document.at_css("body")
    body = Nokogiri::HTML5.fragment(
      sanitize_fragment(source_body&.inner_html.to_s, video_urls: video_urls)
    )
    styles = document.css("style").map(&:text).join("\n")

    <<~HTML
      <!doctype html>
      <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            #{sanitize_stylesheet(styles)}
          </style>
        </head>
        <body#{safe_body_attributes(source_body)}>#{body.to_html}</body>
      </html>
    HTML
  end

  def sanitize_ai_document(html, image_urls: [], video_urls: [])
    document = Nokogiri::HTML5.parse(sanitize_isolated_document(html, video_urls: video_urls))
    allowed_images = image_urls.to_set

    document.css("img").each do |image|
      source = image["src"].to_s
      image.remove unless allowed_images.include?(source)
    end
    document.css("a[href]").each do |link|
      href = link["href"].to_s
      link.remove_attribute("href") unless href.start_with?("#")
    end
    document.to_html
  end

  def sanitize_stylesheet(css)
    cleaned = css.to_s
      .gsub(%r{/\*.*?\*/}m, "")
      .gsub(/@import\b[^;]*;?/i, "")
      .gsub(/url\s*\([^)]*\)/i, "none")
      .gsub(/expression\s*\([^)]*\)/i, "")
      .gsub(/(?:behavior|-moz-binding)\s*:[^;}]*/i, "")
      .gsub(%r{</?style}i, "")
    map_font_families(cleaned)
  end

  def map_inline_fonts(fragment)
    fragment.css("[style]").each do |element|
      element["style"] = map_font_families(element["style"])
    end
  end

  def restrict_video_sources(fragment, video_urls)
    allowed = video_urls.to_set
    fragment.css("video[src], video source[src]").each do |media|
      media.remove_attribute("src") unless allowed.include?(media["src"].to_s)
    end
  end

  def safe_body_attributes(source_body)
    return "" if source_body.blank?

    attributes = {
      "class" => source_body["class"].to_s.scan(/[a-z0-9_-]+/i).join(" ").presence,
      "id" => source_body["id"].to_s[/\A[a-z0-9_-]+\z/i],
      "style" => map_font_families(Rails::HTML::SafeListSanitizer.new.sanitize_css(source_body["style"].to_s)).presence,
      "dir" => source_body["dir"].to_s[/\A(?:ltr|rtl|auto)\z/i],
      "lang" => source_body["lang"].to_s[/\A[a-z0-9-]+\z/i]
    }.compact

    attributes.map { |name, value| %( #{name}="#{CGI.escapeHTML(value)}") }.join
  end

  def map_font_families(css)
    css.to_s.gsub(/font-family\s*:\s*([^;}]+)/i) do
      full_declaration = ::Regexp.last_match(0)
      original_value = ::Regexp.last_match(1).strip
      important = original_value.sub!(/\s*!important\s*\z/i, "") ? " !important" : ""
      primary_name = original_value.split(",", 2).first.to_s.strip.delete_prefix('"').delete_suffix('"').delete_prefix("'").delete_suffix("'")
      category = FONT_MAPPINGS[primary_name.downcase]
      next full_declaration if category.blank?

      %(font-family:"#{primary_name}", #{SYSTEM_FONT_STACKS.fetch(category)}#{important})
    end
  end
end
