class Tag < ApplicationRecord
  has_many :taggings, dependent: :destroy
  has_many :courses, through: :taggings, source: :taggable, source_type: "Course"
  has_many :lessons, through: :taggings, source: :taggable, source_type: "Lesson"

  validates :name, presence: true, uniqueness: { case_insensitive: true }
  validates :color, presence: true,
                    format: { with: /\A#[0-9a-fA-F]{6}\z/, message: "must be a hex colour like #3b82f6" }

  default_scope { order(:name) }

  # Returns a contrasting text colour (dark or light) for the badge background.
  def text_color
    hex = color.delete("#")
    r, g, b = hex.scan(/../).map { |c| c.hex / 255.0 }
    luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
    luminance > 0.5 ? "#111827" : "#ffffff"
  end
end
