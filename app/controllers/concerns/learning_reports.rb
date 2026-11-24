module LearningReports
  extend ActiveSupport::Concern
  include Pagy::Method

  private

  def load_course_report
    enrollments = @course.enrollments
    progresses = @course.progresses

    @enrollment_count = enrollments.count
    @active_learners = @course.active_learners_count
    @completion_rate = @course.completion_rate
    @average_score = @course.average_score
    @average_rating = @course.average_rating

    @enrollments_per_week = enrollments.where(enrolled_at: 12.weeks.ago..).group_by_week(:enrolled_at).count
    @completions_per_week = progresses.completed.where(completed_at: 12.weeks.ago..).group_by_week(:completed_at).count
    @score_distribution = progresses.with_score.group("FLOOR(score / 10) * 10").count
                                     .transform_keys { |k| "#{k.to_i}–#{k.to_i + 9}" }

    @top_learners = enrollments.includes(:user, :progresses)
                                .sort_by { |e| -e.lessons_completed_count }
                                .first(10)

    @pending_by_lesson = QuestionAnswer.pending_marking
      .where(lessons: { course_id: @course.id })
      .group("questions.lesson_id").count

    @lesson_summary = @course.lessons.order(:position).map do |lesson|
      {
        lesson: lesson,
        attempts: lesson.attempts_count,
        completions: lesson.completions_count,
        average_score: lesson.average_score,
        pass_rate: lesson.pass_rate,
        average_rating: lesson.average_rating
      }
    end
  end

  def load_lesson_report
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

    load_free_text_summary
  end

  # One row per free-text question with aggregate marking stats. Answers are
  # never loaded here, so the report stays fast however many there are.
  def load_free_text_summary
    stats = free_text_answers.marking_stats_by_question(@lesson.free_text_pass_level)

    @free_text_summary = @lesson.questions.free_text.map do |question|
      row = stats.fetch(question.id) { { total: 0, scored: 0, passed: 0, pending: 0, average: nil } }
      {
        question: question,
        total: row[:total],
        average: row[:average]&.to_f&.round(1),
        pass_rate: row[:scored].positive? ? (row[:passed] * 100.0 / row[:scored]).round : nil,
        pending: row[:pending]
      }
    end
    @pending_marking = @free_text_summary.sum { |row| row[:pending] }
  end

  QUESTION_REPORT_STATUSES = %w[pending failed passed all].freeze

  # Paginated, filterable answers to one free-text question.
  def load_question_report
    @lesson = @course.lessons.find(params[:id])
    @question = @lesson.questions.free_text.find(params[:question_id])
    pass = @lesson.free_text_pass_level

    scope = free_text_answers.where(question_id: @question.id)
    stats = scope.marking_stats(pass)
    @status_counts = { "pending" => stats[:pending], "failed" => stats[:failed], "passed" => stats[:passed], "all" => stats[:total] }
    @status = QUESTION_REPORT_STATUSES.include?(params[:status]) ? params[:status] : (stats[:pending].positive? ? "pending" : "all")
    @search = params[:q].to_s.strip

    scope = case @status
    when "pending" then scope.pending.order("question_answers.updated_at, question_answers.id")
    when "failed" then scope.failing(pass).order("question_answers.scored_at DESC, question_answers.id DESC")
    when "passed" then scope.passing(pass).order("question_answers.scored_at DESC, question_answers.id DESC")
    else scope.order("question_answers.updated_at DESC, question_answers.id DESC")
    end
    if @search.present?
      term = "%#{ActiveRecord::Base.sanitize_sql_like(@search)}%"
      scope = scope.joins(enrollment: :user).where("users.email ILIKE :term OR users.name ILIKE :term", term: term)
    end

    @pagy, @answers = pagy(:offset, scope.preload(enrollment: :user, question: { lesson: :course }))
    # Marking the last pending answer on the last page leaves that page empty.
    if @answers.empty? && @pagy.page > 1 && @pagy.count.positive?
      redirect_to url_for(request.query_parameters.merge(page: @pagy.last))
    end
  end

  # Free-text answers to this lesson from learners enrolled in its course.
  def free_text_answers
    QuestionAnswer.free_text.from_course_learners.where(questions: { lesson_id: @lesson.id })
  end
end
