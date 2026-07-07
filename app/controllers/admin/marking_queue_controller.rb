class Admin::MarkingQueueController < Admin::BaseController
  def index
    @lessons = Lesson.marking_queue.includes(:course)
  end
end
