class LessonMaterial < ApplicationRecord
  belongs_to :lesson
  has_many :acknowledgements, class_name: "LessonMaterialAcknowledgement", dependent: :destroy

  has_rich_text :body
  has_one_attached :document
  has_one_attached :audio_file
  has_one_attached :image_file

  enum :kind, { pdf: 0, html: 1, raw_html: 2, audio_upload: 3, audio_url: 4, image_upload: 5 }

  SANITIZER     = Rails::HTML::SafeListSanitizer.new
  ALLOWED_TAGS  = %w[p br strong em u s h1 h2 h3 h4 h5 h6 ul ol li
                     blockquote code pre a img figure figcaption
                     table thead tbody tr th td div span].freeze
  ALLOWED_ATTRS = %w[href src alt title class id target rel width height].freeze

  AUDIO_CONTENT_TYPES = %w[
    audio/mpeg audio/vnd.wave audio/x-wav audio/ogg audio/aac
    audio/mp4 audio/x-m4a audio/webm audio/flac audio/x-flac
  ].freeze

  IMAGE_CONTENT_TYPES = %w[
    image/png image/jpeg image/webp image/gif
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
    }
  }.freeze

  KIND_LABELS = {
    "pdf" => "PDF",
    "html" => "Rich text",
    "raw_html" => "Raw HTML",
    "audio_upload" => "Audio (upload)",
    "audio_url" => "Audio (URL)",
    "image_upload" => "Image (upload)"
  }.freeze

  validates :title, presence: true
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
    return unless raw_html?
    self.raw_html_content = SANITIZER.sanitize(
      raw_html_content.to_s,
      tags: ALLOWED_TAGS,
      attributes: ALLOWED_ATTRS
    )
  end
end
