class ProgressesController < ApplicationController
  before_action :authenticate_user!

  def update
    @progress = current_user.progresses.find(params[:id])
    authorize! :read, @progress

    unless manual_completion_allowed?
      redirect_back fallback_location: root_path, alert: t("progresses.flash.cannot_mark_complete")
      return
    end

    if @progress.update(status: :completed)
      redirect_back fallback_location: root_path, notice: t("progresses.flash.saved")
    else
      redirect_back fallback_location: root_path, alert: @progress.errors.full_messages.to_sentence
    end
  end

  private

  def manual_completion_allowed?
    submitted = params.require(:progress)

    submitted.keys.map(&:to_s).sort == [ "status" ] &&
      submitted[:status] == "completed" &&
      @progress.lesson.questions.none? &&
      @progress.lesson.lesson_materials_complete_for?(@progress.enrollment)
  end
end
