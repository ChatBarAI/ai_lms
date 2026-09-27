require "cgi"
require "crass"
require "rails-html-sanitizer"

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

  # Keep these additions local to material HTML; changing Loofah's global lists
  # would also change sanitization of rich text elsewhere in the application.
  INLINE_CSS_PROPERTIES = (Loofah::HTML5::SafeList::ALLOWED_CSS_PROPERTIES + %w[
    box-shadow box-sizing column-gap gap row-gap
    grid-template-columns grid-template-rows grid-template-areas
    grid-auto-columns grid-auto-rows grid-auto-flow
    grid-column grid-column-start grid-column-end grid-row grid-row-start grid-row-end grid-area
    text-transform -webkit-font-smoothing
  ]).freeze
  INLINE_CSS_FUNCTIONS = (Loofah::HTML5::SafeList::ALLOWED_CSS_FUNCTIONS + %w[
    clamp min max minmax repeat fit-content
  ]).freeze

  class MaterialScrubber < Rails::HTML::PermitScrubber
    protected

    def scrub_css_attribute(node)
      style = node.attributes["style"]
      style.value = SafeHtmlPolicy.sanitize_inline_css(style.value) if style
    end
  end

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
    scrubber = MaterialScrubber.new
    scrubber.tags = ALLOWED_TAGS + (video_urls.any? ? VIDEO_TAGS : [])
    scrubber.attributes = ALLOWED_ATTRIBUTES + (video_urls.any? ? VIDEO_ATTRIBUTES : [])
    sanitized = Rails::HTML::SafeListSanitizer.new.sanitize(
      source.to_html, scrubber: scrubber
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

  def sanitize_inline_css(css)
    Crass.parse_properties(css.to_s).filter_map do |property|
      next unless property[:node] == :property

      name = property[:name].downcase
      next unless INLINE_CSS_PROPERTIES.include?(name) ||
        Loofah::HTML5::SafeList::ALLOWED_SVG_PROPERTIES.include?(name) ||
        Loofah::HTML5::SafeList::SHORTHAND_CSS_PROPERTIES.include?(name.split("-").first)
      next unless safe_css_values?(property[:children])

      value = Crass::Parser.stringify(property[:children]).strip
      next if value.empty?

      "#{name}:#{value}#{' !important' if property[:important]};"
    end.join
  end

  def safe_css_values?(nodes)
    nodes.all? do |node|
      case node[:node]
      when :function
        # Check decoded function names and nested arguments so escaped URLs or
        # URLs inside otherwise allowed functions cannot bypass the policy.
        INLINE_CSS_FUNCTIONS.include?(node[:name].downcase) && safe_css_values?(node[:value])
      when :simple_block
        [ "(", "[" ].include?(node[:start]) && safe_css_values?(node[:value])
      when :ident, :number, :dimension, :percentage, :hash, :string, :whitespace, :comment, :comma
        true
      when :delim
        %w[+ - * /].include?(node[:value])
      else
        false
      end
    end
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
      "style" => map_font_families(sanitize_inline_css(source_body["style"].to_s)).presence,
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
