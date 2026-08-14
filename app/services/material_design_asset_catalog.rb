require "cgi"
require "uri"

class MaterialDesignAssetCatalog
  Entry = Data.define(:token, :url, :name, :description, :alt_text, :source, :referenced_in_source)

  def initialize(material)
    @material = material
  end

  def entries
    @entries ||= manual_entries + imported_entries
  end

  def design_references
    @design_references ||= material.material_design_assets.design_reference
      .includes(file_attachment: :blob).select { |asset| asset.file.attached? }
  end

  def tokenize_html(html)
    document = Nokogiri::HTML5.parse(html.to_s)
    entries_by_url = entries.index_by(&:url)
    entries_by_path = entries.index_by { |entry| URI.parse(entry.url).path }
    imported_by_filename = entries.select { |entry| entry.source == :imported }.index_by(&:name)
    document.css("img[src]").each do |image|
      source = image["src"].to_s
      source_path = URI.parse(source).path
      filename = CGI.unescape(File.basename(source_path))
      entry = entries_by_url[source] || entries_by_path[source_path] || imported_by_filename[filename]
      image["src"] = entry.token if entry
    rescue URI::InvalidURIError
      next
    end
    document.to_html
  end

  private

  attr_reader :material

  def manual_entries
    material.material_design_assets.includes(file_attachment: :blob).filter_map do |asset|
      next unless asset.file.attached? && asset.content?

      url = routes.material_design_asset_file_path(
        asset.signed_id(purpose: :material_design_asset), v: asset.file.blob_id
      )
      Entry.new(
        token: asset.prompt_token,
        url: url,
        name: asset.name,
        description: asset.description,
        alt_text: asset.alt_text,
        source: :manual,
        referenced_in_source: source_references?(asset.prompt_token, url, URI.parse(url).path)
      )
    end
  end

  def imported_entries
    imported_alt_text = alt_text_by_filename
    material.imported_assets.attachments.includes(:blob).map do |attachment|
      filename = attachment.blob.filename.to_s
      signed_id = ActiveStorage.verifier.generate(
        attachment.id, purpose: :material_design_imported_asset
      )
      token = "asset://imported/#{signed_id}"
      url = routes.material_design_imported_asset_file_path(signed_id)
      Entry.new(
        token: token,
        url: url,
        name: filename,
        description: "Image imported with the existing material (#{filename})",
        alt_text: imported_alt_text[filename],
        source: :imported,
        referenced_in_source: imported_filename_referenced?(filename) || source_references?(token, url)
      )
    end
  end

  def alt_text_by_filename
    document = Nokogiri::HTML5.parse(material.raw_html_content.to_s)
    document.css("img[src]").each_with_object({}) do |image, alt_text|
      filename = CGI.unescape(File.basename(URI.parse(image["src"].to_s).path))
      alt_text[filename] ||= image["alt"].to_s.presence
    rescue URI::InvalidURIError
      next
    end
  end

  def imported_filename_referenced?(filename)
    source_image_filenames.include?(filename)
  end

  def source_image_filenames
    @source_image_filenames ||= begin
      document = Nokogiri::HTML5.parse(material.raw_html_content.to_s)
      document.css("img[src]").filter_map do |image|
        CGI.unescape(File.basename(URI.parse(image["src"].to_s).path))
      rescue URI::InvalidURIError
        nil
      end.to_set
    end
  end

  def source_references?(*references)
    source = material.raw_html_content.to_s
    references.any? { |reference| source.include?(reference) }
  end

  def routes
    Rails.application.routes.url_helpers
  end
end
