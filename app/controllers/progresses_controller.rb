class ProgressesController < ApplicationController
  before_action :authenticate_user!

  def update
    @progress = Progress.find(params[:id])
    authorize! :update, @progress
    @progress.assign_attributes(progress_params)
    if @progress.save
      redirect_back fallback_location: root_path, notice: "Progress saved."
    else
      redirect_back fallback_location: root_path, alert: @progress.errors.full_messages.to_sentence
    end
  end

  private

  def progress_params
    params.require(:progress).permit(:status, :score)
  end
end
