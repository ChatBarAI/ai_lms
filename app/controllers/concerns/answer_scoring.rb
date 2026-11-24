# Controller side of scoring an answer by hand, shared by the admin and
# instructor score actions. The rules live in ManualAnswerScorer.
module AnswerScoring
  extend ActiveSupport::Concern

  private

  def score_answer!(answer)
    ManualAnswerScorer.call(answer, params.require(:question_answer).permit(:ai_score).fetch(:ai_score))
  end

  # Only allow returning to a known marking page (queue or question report),
  # keeping its query string so filters and the page number survive.
  def marking_return_path(*allowed)
    path = params[:return_to].to_s
    path if allowed.any? { |prefix| path == prefix || path.start_with?("#{prefix}?") }
  end
end
