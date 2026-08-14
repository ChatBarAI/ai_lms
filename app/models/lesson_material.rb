class LessonMaterial < ApplicationRecord
  AI_DESIGN_STARTER_HTML = <<~HTML.freeze
    <!doctype html>
    <html lang="en">
      <head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"></head>
      <body></body>
    </html>
  HTML

  belongs_to :lesson
  belongs_to :source_material, class_name: "LessonMaterial", optional: true
  belongs_to :copied_by, class_name: "User", optional: true
  has_many :material_copies, class_name: "LessonMaterial",
                             foreign_key: :source_material_id, dependent: :nullify,
                             inverse_of: :source_material
  has_many :acknowledgements, class_name: "LessonMaterialAcknowledgement", dependent: :destroy
  has_many :material_design_revisions, dependent: :destroy
  has_many :material_design_assets, dependent: :destroy

  has_rich_text :body
  has_one_attached :document
  has_one_attached :audio_file
  has_one_attached :image_file
  has_one_attached :video_file
  has_many_attached :imported_assets

  attr_accessor :google_doc_zip

  enum :kind, { pdf: 0, html: 1, raw_html: 2, audio_upload: 3, audio_url: 4, image_upload: 5, video_upload: 6, video_url: 7, google_doc: 8, raw_html_iframe: 9, web_page: 10 }

  AUDIO_CONTENT_TYPES = %w[
    audio/mpeg audio/vnd.wave audio/x-wav audio/ogg audio/aac
    audio/mp4 audio/x-m4a audio/webm audio/flac audio/x-flac
  ].freeze

  IMAGE_CONTENT_TYPES = %w[
    image/png image/jpeg image/webp image/gif
  ].freeze

  VIDEO_CONTENT_TYPES = %w[
    video/mp4 video/webm video/ogg
  ].freeze

  KIND_CONTENT_REQUIREMENTS = {
    "pdf" => {
      field: :document,
      message: "must be attached for a PDF material",
      valid: ->(material) { material.document.attached? }
    },
    "html" => {
      field: :body,
      message: "can't be blank",
      valid: ->(material) { material.body.present? }
    },
    "raw_html" => {
      field: :raw_html_content,
      message: "can't be blank",
      valid: ->(material) { material.raw_html_content.present? }
    },
    "raw_html_iframe" => {
      field: :raw_html_content,
      message: "can't be blank",
      valid: ->(material) { material.raw_html_content.present? }
    },
    "google_doc" => {
      field: :google_doc_zip,
      message: "must be imported from a Google Docs Web Page ZIP",
      valid: ->(material) { material.raw_html_content.present? }
    },
    "web_page" => {
      field: :raw_html_content,
      message: "must be imported from a public web page URL",
      valid: ->(material) { material.raw_html_content.present? }
    },
    "audio_upload" => {
      field: :audio_file,
      message: "must be attached for an uploaded audio material",
      valid: ->(material) { material.audio_file.attached? }
    },
    "audio_url" => {
      field: :url,
      message: "can't be blank",
      valid: ->(material) { material.url.present? }
    },
    "image_upload" => {
      field: :image_file,
      message: "must be attached for an uploaded image material",
      valid: ->(material) { material.image_file.attached? }
    },
    "video_upload" => {
      field: :video_file,
      message: "must be attached for an uploaded video material",
      valid: ->(material) { material.video_file.attached? }
    },
    "video_url" => {
      field: :url,
      message: "can't be blank",
      valid: ->(material) { material.url.present? }
    }
  }.freeze

  KIND_LABELS = {
    "pdf" => "PDF",
    "html" => "Rich text",
    "raw_html" => "Raw HTML",
    "raw_html_iframe" => "Raw HTML (isolated iframe)",
    "google_doc" => "Google Docs import",
    "web_page" => "Web page import",
    "audio_upload" => "Audio (upload)",
    "audio_url" => "Audio (URL)",
    "image_upload" => "Image (upload)",
    "video_upload" => "Video (upload)",
    "video_url" => "Video (URL)"
  }.freeze

  validates :title, presence: true
  validates :url, presence: true, if: :web_page?
  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :content_matches_kind
  validates :document, content_type: "application/pdf",
                       size: { less_than: 25.megabytes },
                       if: -> { document.attached? }
  validates :audio_file,
            content_type: AUDIO_CONTENT_TYPES,
            size: { less_than: 50.megabytes },
            if: -> { audio_file.attached? }
  validates :image_file,
            content_type: IMAGE_CONTENT_TYPES,
            size: { less_than: 10.megabytes },
            if: -> { image_file.attached? }
  validates :video_file,
            content_type: VIDEO_CONTENT_TYPES,
            size: { less_than: 100.megabytes },
            if: -> { video_file.attached? }

  before_validation :assign_position, on: :create
  before_validation :sanitize_raw_html

  scope :required_only, -> { where(required: true) }

  def acknowledged_by?(enrollment)
    return false if enrollment.blank?
    acknowledgements.exists?(enrollment_id: enrollment.id)
  end

  def audio?
    audio_upload? || audio_url?
  end

  def video?
    video_upload? || video_url?
  end

  def ai_designable?
    html? || raw_html? || raw_html_iframe? || google_doc? || web_page?
  end

  def blank_ai_design_source?
    return false unless raw_html_iframe? && raw_html_content.present?

    document = Nokogiri::HTML5.parse(raw_html_content)
    document.at_css("body")&.inner_html.to_s.strip.blank? &&
      document.css("style").all? { |style| style.text.strip.blank? }
  end

  def public_to_guests?
    lesson&.public_to_guests?
  end

  def kind_label
    KIND_LABELS[kind]
  end

  private

  def assign_position
    self.position = (lesson&.lesson_materials&.maximum(:position).to_i + 1) if position.to_i.zero?
  end

  def content_matches_kind
    requirement = KIND_CONTENT_REQUIREMENTS[kind]
    return if requirement.blank? || requirement[:valid].call(self)

    errors.add(requirement[:field], requirement[:message])
  end

  def sanitize_raw_html
    self.raw_html_content = SafeHtmlPolicy.sanitize_fragment(raw_html_content) if raw_html?
    self.raw_html_content = SafeHtmlPolicy.sanitize_isolated_document(raw_html_content) if raw_html_iframe?
  end
end
