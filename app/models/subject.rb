class Subject < ApplicationRecord
  has_many :courses, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true
  validates :slug, presence: true, uniqueness: true,
                   format: { with: /\A[a-z0-9-]+\z/, message: "only lowercase letters, digits and hyphens" }

  before_validation :assign_slug, on: :create

  def to_param
    slug.presence || id.to_s
  end

  private

  def assign_slug
    self.slug = name.to_s.parameterize if slug.blank?
  end
end
