class QuestionGenerationTask < ApplicationRecord
  belongs_to :lesson

  STATUSES = %w[pending queued succeeded failed].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :callback_secret, presence: true, uniqueness: true

  before_validation :assign_callback_secret, on: :create

  scope :recent, -> { order(created_at: :desc) }

  STATUSES.each do |s|
    define_method("#{s}?") { status == s }
  end

  def mark_queued!(cbai_task_id:, task_payload:)
    update!(status: "queued", cbai_task_id: cbai_task_id, task_payload: task_payload)
  end

  def mark_succeeded!(response_payload:, questions_created_count:)
    update!(
      status: "succeeded",
      response_payload: response_payload,
      questions_created_count: questions_created_count,
      error_message: nil
    )
  end

  def mark_failed!(error_message, response_payload: nil)
    update!(status: "failed", error_message: error_message.to_s[0, 1000], response_payload: response_payload)
  end

  private

  def assign_callback_secret
    self.callback_secret ||= SecureRandom.urlsafe_base64(32)
  end
end
