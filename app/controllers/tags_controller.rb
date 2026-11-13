class TagsController < ApplicationController
  def show
    @tag = Tag.find(params[:id])
    course_scope = Course.catalog_visible_to(current_user)
    @courses = @tag.courses.merge(course_scope).includes(:subject, :tags).order(:title)
    @lessons = @tag.lessons.accessible_by(current_ability).published.joins(:course).merge(course_scope).includes(:tags, course: :subject).order(:title)
  end
end
