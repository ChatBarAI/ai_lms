class MaterialDesignRevision < ApplicationRecord
  STATUSES = %w[queued generating ready failed accepted].freeze

  belongs_to :lesson_material
  belongs_to :ai_model_configuration
  belongs_to :created_by, class_name: "User"
  belongs_to :parent_revision, class_name: "MaterialDesignRevision", optional: true
  has_many :child_revisions, class_name: "MaterialDesignRevision",
                             foreign_key: :parent_revision_id, dependent: :nullify

  validates :request, presence: true, length: { maximum: 10_000 }
  validates :status, inclusion: { in: STATUSES }
  validates :sanitized_html, presence: true, if: -> { ready? || accepted? }
  validates :lesson_material_id, uniqueness: {
    conditions: -> { where(status: %w[queued generating]) },
    message: "already has a design generation in progress"
  }, if: -> { queued? || generating? }
  validate :parent_belongs_to_same_material

  scope :recent, -> { order(created_at: :desc) }

  STATUSES.each { |value| define_method("#{value}?") { status == value } }

  def self.stream_name_for(lesson_material_id)
    "material_design_revisions:#{lesson_material_id}"
  end

  def self.broadcast_payload(revision)
    {
      revision_id: revision.id,
      status: revision.status,
      error_message: revision.failed? ? revision.error_message : nil
    }
  end

  def broadcast_status
    ActionCable.server.broadcast(
      self.class.stream_name_for(lesson_material_id),
      self.class.broadcast_payload(self).merge(event: "status_changed")
    )
  rescue StandardError => error
    Rails.logger.warn(
      "[MaterialDesignRevision] Could not broadcast status for revision #{id}: #{error.message}"
    )
    nil
  end

  def accept!
    unless ready?
      errors.add(:status, "must be ready before it can be accepted")
      raise ActiveRecord::RecordInvalid, self
    end

    transaction do
      lesson_material.update!(kind: :raw_html_iframe, raw_html_content: sanitized_html)
      lesson_material.material_design_revisions.where(status: "accepted").where.not(id: id)
                     .update_all(status: "ready", accepted_at: nil)
      update!(status: "accepted", accepted_at: Time.current)
    end
  end

  def estimated_cost_cents
    ai_model_configuration.estimated_cost_cents(
      input_tokens: input_tokens, output_tokens: output_tokens
    )
  end

  private

  def parent_belongs_to_same_material
    return if parent_revision.blank? || parent_revision.lesson_material_id == lesson_material_id

    errors.add(:parent_revision, "must belong to the same material")
  end
end
