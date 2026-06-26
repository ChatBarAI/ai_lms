class TagsController < ApplicationController
  def show
    @tag = Tag.find(params[:id])
    @courses = @tag.courses.published.visible_to(current_user).includes(:subject, :tags).order(:title)
    @lessons = @tag.lessons.published.joins(:course).merge(Course.visible_to(current_user)).includes(:tags, course: :subject).order(:title)
  end
end
