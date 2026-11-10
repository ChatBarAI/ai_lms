class ChatbarNamesController < ApplicationController
  before_action :authenticate_user!

  def create
    course = Course.find_by(slug: params[:course_id]) || Course.find(params[:course_id])
    authorize! :update, course

    details = CbaiClient.new(api_key: params[:api_key]).details
    render json: { name: CbaiClient.name_from_details(details) }
  rescue CbaiClient::Error
    render json: { error: "Could not look up ChatBar name. Check the API key and try again." }, status: :unprocessable_entity
  end
end
