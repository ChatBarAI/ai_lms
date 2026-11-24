class Admin::MarkingQueueController < Admin::BaseController
  include MarkingWorkspace

  def index
    load_marking_queue(Lesson.marking_queue)
  end
end
