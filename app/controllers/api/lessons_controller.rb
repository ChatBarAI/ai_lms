class Api::LessonsController < ApplicationController
  protect_from_forgery with: :null_session
  skip_before_action :authenticate_user!, raise: false

  def show
    lesson = Lesson.find_by!(cbai_token: params[:token])
    render json: {
      id: lesson.id,
      title: lesson.title,
      course: { id: lesson.course_id, title: lesson.course.title, slug: lesson.course.slug },
      position: lesson.position,
      published: lesson.published?,
      cbai_token: lesson.cbai_token,
      average_rating: lesson.average_rating
    }
  end
end
