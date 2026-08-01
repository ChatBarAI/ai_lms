require "zip"
require "cgi"
require "pathname"
require "stringio"

class GoogleDocImportService
  class ImportError < StandardError; end

  MAX_ARCHIVE_SIZE = 25.megabytes
  MAX_EXTRACTED_SIZE = 50.megabytes
  MAX_ENTRIES = 200

  IMAGE_CONTENT_TYPES = {
    ".gif" => "image/gif",
    ".jpeg" => "image/jpeg",
    ".jpg" => "image/jpeg",
    ".png" => "image/png",
    ".webp" => "image/webp"
  }.freeze

  def initialize(material:, upload:)
    @material = material
    @upload = upload
    @created_blobs = []
  end

  def call
    raise ImportError, "Choose the ZIP downloaded from Google Docs." if upload.blank?
    raise ImportError, "The Google Docs ZIP must be smaller than 25 MB." if upload.size.to_i > MAX_ARCHIVE_SIZE

    imported = read_archive
    old_assets = material.imported_assets.to_a

    material.title = inferred_title(imported.fetch(:html)) if material.title.blank?
    material.raw_html_content = build_document(imported.fetch(:html), imported.fetch(:images))
    material.save!
    @material_saved = true
    old_assets.each(&:purge)
    material
  rescue Zip::Error => error
    cleanup_created_blobs
    raise ImportError, "The uploaded file is not a valid Google Docs ZIP (#{error.message})."
  rescue ImportError, ActiveRecord::RecordInvalid
    cleanup_created_blobs
    raise
  rescue StandardError
    cleanup_created_blobs
    raise
  end

  private

  attr_reader :material, :upload

  def read_archive
    html_entries = []
    images = {}

    upload.tempfile.rewind
    Zip::File.open_buffer(upload.tempfile) do |archive|
      files = archive.reject(&:directory?)
      raise ImportError, "The ZIP contains too many files." if files.size > MAX_ENTRIES
      raise ImportError, "The expanded ZIP is too large." if files.sum(&:size) > MAX_EXTRACTED_SIZE

      files.each do |entry|
        validate_entry_name!(entry.name)
        extension = File.extname(entry.name).downcase

        if %w[.html .htm].include?(extension)
          html_entries << [ entry.name, entry.get_input_stream.read ]
        elsif IMAGE_CONTENT_TYPES.key?(extension)
          images[normalise_path(entry.name)] = {
            bytes: entry.get_input_stream.read,
            filename: File.basename(entry.name),
            content_type: IMAGE_CONTENT_TYPES.fetch(extension)
          }
        end
      end
    end

    raise ImportError, "The ZIP does not contain an HTML document." if html_entries.empty?
    raise ImportError, "The ZIP contains more than one HTML document." if html_entries.many?

    { html: html_entries.first.last, images: images }
  ensure
    upload.tempfile.rewind
  end

  def validate_entry_name!(name)
    clean = name.to_s.tr("\\", "/")
    if clean.start_with?("/") || clean.split("/").include?("..") || clean.include?("\0")
      raise ImportError, "The ZIP contains an unsafe file path."
    end
  end

  def build_document(source_html, images)
    document = Nokogiri::HTML5.parse(source_html)
    imported_css = document.css("style").map(&:text).join("\n")
    source_body = document.at_css("body")
    body_html = source_body&.inner_html.to_s
    fragment = Nokogiri::HTML5.fragment(SafeHtmlPolicy.sanitize_fragment(body_html))
    rewrite_links!(fragment)
    rewrite_images!(fragment, images)

    <<~HTML
      <!doctype html>
      <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            #{base_css}
            #{SafeHtmlPolicy.sanitize_stylesheet(imported_css)}
            #{responsive_css}
          </style>
        </head>
        <body#{SafeHtmlPolicy.safe_body_attributes(source_body)}>#{fragment.to_html}</body>
      </html>
    HTML
  end

  def rewrite_links!(fragment)
    fragment.css("a").each do |link|
      href = link["href"].to_s
      unless href.start_with?("https://", "http://", "mailto:", "#")
        link.remove_attribute("href")
        next
      end

      next if href.start_with?("#")
      link["target"] = "_blank"
      link["rel"] = "noopener noreferrer"
    end
  end

  def rewrite_images!(fragment, images)
    asset_urls = {}

    fragment.css("img").each do |image|
      source = CGI.unescape(image["src"].to_s.split(/[?#]/, 2).first.to_s)
      archive_path = normalise_path(source)
      imported_image = images[archive_path]

      unless imported_image
        image.remove
        next
      end

      asset_urls[archive_path] ||= begin
        blob = ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new(imported_image.fetch(:bytes)),
          filename: imported_image.fetch(:filename),
          content_type: imported_image.fetch(:content_type)
        )
        @created_blobs << blob
        material.imported_assets.attach(blob)
        Rails.application.routes.url_helpers.rails_storage_proxy_path(blob, disposition: "inline", only_path: true)
      end
      image["src"] = asset_urls.fetch(archive_path)
      image.remove_attribute("srcset")
      image["loading"] = "lazy"
    end
  end

  def normalise_path(path)
    Pathname.new(path.to_s.tr("\\", "/")).cleanpath.to_s.sub(%r{\A\./}, "")
  end

  def inferred_title(source_html)
    document_title = Nokogiri::HTML5.parse(source_html).at_css("title")&.text.to_s.squish
    return document_title if document_title.present?

    File.basename(upload.original_filename.to_s, File.extname(upload.original_filename.to_s)).presence || "Imported Google document"
  end

  def cleanup_created_blobs
    return if @material_saved

    @created_blobs.each(&:purge)
  end

  def base_css
    <<~CSS
      html { color: #111827; background: #fff; }
      body { margin: 0; padding: 0; }
      img { max-width: 100%; height: auto; }
      a { color: #4f46e5; }
    CSS
  end

  def responsive_css
    <<~CSS
      @media (max-width: 720px) {
        body {
          max-width: 100% !important;
          padding-left: 1rem !important;
          padding-right: 1rem !important;
        }
        img { max-width: 100% !important; height: auto !important; }
        table { max-width: 100%; }
      }
    CSS
  end
end
