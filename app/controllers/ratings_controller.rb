class RatingsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_lesson
  before_action :ensure_ratings_enabled!, only: [ :create, :update ]

  def create
    @rating = Rating.find_or_initialize_by(user: current_user, lesson: @lesson)
    @rating.assign_attributes(rating_params)
    authorize! :create, @rating
    if @rating.save
      redirect_to course_lesson_path(@lesson.course, @lesson), notice: t("ratings.flash.created")
    else
      redirect_to course_lesson_path(@lesson.course, @lesson), alert: @rating.errors.full_messages.to_sentence
    end
  end

  def update
    @rating = Rating.find(params[:id])
    authorize! :update, @rating
    if @rating.update(rating_params)
      redirect_to course_lesson_path(@lesson.course, @lesson), notice: t("ratings.flash.updated")
    else
      redirect_to course_lesson_path(@lesson.course, @lesson), alert: @rating.errors.full_messages.to_sentence
    end
  end

  def destroy
    rating = Rating.find(params[:id])
    authorize! :destroy, rating
    rating.destroy
    redirect_to course_lesson_path(@lesson.course, @lesson), notice: t("ratings.flash.removed"), status: :see_other
  end

  private

  def set_lesson
    @lesson = Lesson.find(params[:lesson_id])
  end

  def rating_params
    params.require(:rating).permit(:stars, :comment)
  end

  def ensure_ratings_enabled!
    return if @lesson.ratings_enabled?

    redirect_to course_lesson_path(@lesson.course, @lesson), alert: t("ratings.flash.disabled")
  end
end
