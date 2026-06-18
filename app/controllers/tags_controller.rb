class TagsController < ApplicationController
  def show
    @tag = Tag.find(params[:id])
    @courses = @tag.courses.published.includes(:subject, :tags).order(:title)
    @lessons = @tag.lessons.published.includes(:tags, course: :subject).order(:title)
  end
end
