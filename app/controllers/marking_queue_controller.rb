class MarkingQueueController < ApplicationController
  include MarkingWorkspace
  before_action :authenticate_user!

  def index
    authorize! :access, :marking_queue
    load_marking_queue(Lesson.marking_queue.accessible_by(current_ability, :report))
    render "admin/marking_queue/index"
  end
end
