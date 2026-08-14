class MaterialDesignAsset < ApplicationRecord
  CONTENT_TYPES = %w[image/png image/jpeg image/webp image/gif].freeze
  ROLES = %w[content design_reference].freeze

  belongs_to :lesson_material
  belongs_to :created_by, class_name: "User"
  has_one_attached :file

  validates :name, presence: true
  validates :file, attached: true, content_type: CONTENT_TYPES, size: { less_than: 10.megabytes }

  enum :role, { content: "content", design_reference: "design_reference" },
       default: :content, validate: true

  def prompt_token
    "asset://#{signed_id(purpose: :material_design_asset)}"
  end
end
