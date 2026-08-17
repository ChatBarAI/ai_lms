class MaterialDesignAsset < ApplicationRecord
  IMAGE_CONTENT_TYPES = %w[image/png image/jpeg image/webp image/gif].freeze
  VIDEO_CONTENT_TYPES = %w[video/mp4 video/webm video/ogg].freeze
  CONTENT_TYPES = (IMAGE_CONTENT_TYPES + VIDEO_CONTENT_TYPES).freeze
  IMAGE_MAX_SIZE = 10.megabytes
  VIDEO_MAX_SIZE = 100.megabytes
  ROLES = %w[content design_reference].freeze

  belongs_to :lesson_material
  belongs_to :created_by, class_name: "User"
  has_one_attached :file

  validates :name, presence: true
  validates :file, attached: true, content_type: CONTENT_TYPES, size: { less_than: VIDEO_MAX_SIZE }
  validate :image_size_is_within_limit
  validate :video_is_page_content

  enum :role, { content: "content", design_reference: "design_reference" },
       default: :content, validate: true

  def prompt_token
    "asset://#{signed_id(purpose: :material_design_asset)}"
  end

  def image?
    file.attached? && IMAGE_CONTENT_TYPES.include?(file.blob.content_type)
  end

  def video?
    file.attached? && VIDEO_CONTENT_TYPES.include?(file.blob.content_type)
  end

  private

  def image_size_is_within_limit
    return unless image? && file.blob.byte_size >= IMAGE_MAX_SIZE

    errors.add(:file, "must be less than 10 MB for an image")
  end

  def video_is_page_content
    return unless video? && design_reference?

    errors.add(:role, "must be page content for a video")
  end
end
