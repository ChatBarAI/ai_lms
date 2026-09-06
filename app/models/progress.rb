class Progress < ApplicationRecord
  self.table_name = "progresses"

  belongs_to :enrollment
  belongs_to :lesson
  has_many :quiz_attempts, dependent: :destroy

  enum :status, { not_started: 0, in_progress: 1, completed: 2 }, default: :not_started

  validates :enrollment_id, uniqueness: { scope: :lesson_id }
  validates :score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true

  scope :completed_between, ->(range) { range ? where(completed_at: range) : all }
  scope :with_score, -> { where.not(score: nil) }

  before_save :stamp_completed_at

  def next_attempt_number
    quiz_attempts.maximum(:attempt_number).to_i + 1
  end

  # Progress measures completion; score remains the unmodified quiz mark.
  def completion_percentage
    return 100.0 if completed?

    material_fraction = materials_completion_fraction
    return (material_fraction * 100).round(1) if lesson.questions.empty?

    material_weight = completion_materials.empty? ? 0 : 20
    percentage = material_fraction * material_weight + score.to_f * (100 - material_weight) / 100
    [ percentage.round(1), 99.0 ].min
  end

  def refresh_material_progress!
    return if completed?
    return if materials_completion_fraction.zero?

    self.status = if lesson.questions.empty? && materials_completion_fraction == 1.0
      :completed
    else
      :in_progress
    end
    save! if changed?
  end

  private

  def completion_materials
    materials = lesson.lesson_materials.to_a
    required = materials.select(&:required?)
    required.presence || materials
  end

  def materials_completion_fraction
    ids = completion_materials.map(&:id)
    return 0.0 if ids.empty?

    acknowledged = enrollment.lesson_material_acknowledgements.where(lesson_material_id: ids).count
    acknowledged.to_f / ids.size
  end

  def stamp_completed_at
    if status_changed? && completed? && completed_at.blank?
      self.completed_at = Time.current
    end
  end
end
