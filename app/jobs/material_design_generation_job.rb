class MaterialDesignGenerationJob < ApplicationJob
  queue_as :default

  def perform(revision_id)
    revision = MaterialDesignRevision.find(revision_id)
    return unless revision.queued? || revision.generating?

    MaterialDesignGenerationService.new(revision).call
  rescue ActiveRecord::RecordNotFound
    nil
  end
end
