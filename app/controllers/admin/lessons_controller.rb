class Admin::LessonsController < Admin::BaseController
  before_action :set_course

  def index
    @lessons = @course.lessons.includes(:questions, :lesson_materials).order(:position)
  end

  def report
    @lesson = @course.lessons.find(params[:id])

    progresses = @lesson.progresses
    @attempts = progresses.count
    @completions = progresses.where.not(completed_at: nil).count
    @average_score = @lesson.average_score
    @pass_rate = @lesson.pass_rate
    @average_rating = @lesson.average_rating

    @completions_per_week = progresses.where.not(completed_at: nil)
                                       .where(completed_at: 12.weeks.ago..)
                                       .group_by_week(:completed_at).count
    @ratings_distribution = @lesson.ratings.group(:stars).count

    @recent_attempts = progresses.includes(enrollment: :user)
                                  .order(updated_at: :desc).limit(20)
    @recent_comments = @lesson.ratings.where.not(comment: [ nil, "" ])
                                .includes(:user).order(created_at: :desc).limit(10)

    @ai_answers = QuestionAnswer
      .joins(:question, enrollment: :user)
      .where(questions: { lesson_id: @lesson.id })
      .order("questions.position, users.email")
      .select("question_answers.*, questions.prompt AS question_body, questions.correct_answer AS expected_answer, users.email AS user_email")
  end

  private

  def set_course
    @course = Course.find_by(slug: params[:course_id]) || Course.find(params[:course_id])
  end
end
