class Api::LessonsController < ApplicationController
  protect_from_forgery with: :null_session
  skip_before_action :authenticate_user!, raise: false

  # Public embed API: callers are usually anonymous widgets on customer sites, so
  # the general catalogue Ability (published / public / guest access) must not
  # apply here. Only paid courses are gated, and always with a JSON response.
  def show
    lesson = Lesson.find_by!(cbai_token: params[:token])
    unless CourseAccess.allowed?(current_user, lesson.course)
      return render json: { error: "forbidden" }, status: :forbidden
    end

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
