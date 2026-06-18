class ScoringChannel < ApplicationCable::Channel
  def subscribed
    progress_id = params[:progress_id].to_i
    progress = Progress.find_by(id: progress_id)

    if progress && progress.enrollment.user == current_user
      stream_from "scoring:#{progress_id}"
    else
      reject
    end
  end
end
