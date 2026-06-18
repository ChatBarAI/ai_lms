class LessonMaterialAcknowledgement < ApplicationRecord
  belongs_to :lesson_material
  belongs_to :enrollment

  validates :enrollment_id, uniqueness: { scope: :lesson_material_id }
  validates :acknowledged_at, presence: true

  before_validation :stamp_acknowledged_at

  private

  def stamp_acknowledged_at
    self.acknowledged_at ||= Time.current
  end
end
