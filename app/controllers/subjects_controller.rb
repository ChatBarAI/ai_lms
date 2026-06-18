class SubjectsController < ApplicationController
  def index
    @subjects = Subject.order(:name)
  end

  def show
    @subject = Subject.find_by!(slug: params[:id]) rescue Subject.find(params[:id])
    @courses = @subject.courses.published.includes(:tags).order(published_at: :desc)
  end
end
