class LessonsController < ApplicationController
  before_action :authenticate_user!, only: [ :new, :create, :edit, :update, :destroy, :start, :submit_quiz, :publish, :unpublish, :video_youtube_edit, :video_youtube_update, :video_upload_edit, :video_upload_update, :video_chatbar, :video_synthesia, :video_heygen, :import_recording, :import_synthesia_video, :import_heygen_video, :destroy_video, :poster_edit, :poster_update, :destroy_poster ]
  before_action :set_course
  load_and_authorize_resource through: :course
  skip_authorize_resource only: [ :start, :submit_quiz ]

  def index
    @lessons = @course.lessons
  end

  def show
    @enrollment = current_user&.enrollments&.find_by(course_id: @course.id)
    if @enrollment
      @progress = @enrollment.progresses.find_or_create_by!(lesson_id: @lesson.id)
      @quiz_attempts = @progress.quiz_attempts.ordered.to_a
      @ai_scoring_pending = @progress.persisted? && !@progress.completed? && QuestionAnswer
        .joins(:question)
        .where(enrollment_id: @enrollment.id, questions: { lesson_id: @lesson.id, kind: Question.kinds[:free_text] })
        .where(ai_score: nil)
        .exists?

      if @ai_scoring_pending && @progress.scoring_submitted_at.present? &&
          @progress.scoring_submitted_at < 5.minutes.ago
        fail_scoring!(@progress, @enrollment, @lesson)
        @progress.reload
        @quiz_attempts = @progress.quiz_attempts.ordered.to_a
        @ai_scoring_pending = false
        flash.now[:alert] = t("lessons.flash.ai_marking_timeout", quiz_l: helpers.terms[:quiz_l])
      end

      @latest_quiz_answers = latest_quiz_answers_for(@enrollment, @lesson) if @progress.score.present? && !@ai_scoring_pending
    end
    if @lesson.retry_incorrect_only? && @enrollment && @progress&.persisted?
      @questions = @lesson.incorrect_questions_for(@enrollment)
      @retry_mode = true
    else
      @questions = @lesson.questions.to_a
      @retry_mode = false
    end
    @user_rating = current_user && Rating.find_by(user_id: current_user.id, lesson_id: @lesson.id)

    @anam_session_token = nil
    @anam_session_token = fetch_anam_session_token if @lesson.anam_enabled?
  end

  def start
    enrollment = current_user.enrollments.find_by(course_id: @course.id)
    if enrollment && !@lesson.lesson_materials_complete_for?(enrollment)
      redirect_to course_lesson_path(@course, @lesson), alert: t("lessons.flash.complete_required_materials") and return
    end
    if enrollment
      progress = enrollment.progresses.find_or_create_by(lesson_id: @lesson.id)
      progress.update(status: :in_progress) if progress.not_started?
    end
    redirect_to course_lesson_path(@course, @lesson)
  end

  def submit_quiz
    authorize! :read, @lesson

    enrollment = current_user&.enrollments&.find_by(course_id: @course.id)
    return redirect_to(course_lesson_path(@course, @lesson), alert: t("lessons.flash.enrol_to_submit")) unless enrollment
    return redirect_to(course_lesson_path(@course, @lesson), alert: t("lessons.flash.complete_required_materials")) unless @lesson.lesson_materials_complete_for?(enrollment)

    answers = submission_answers
    return redirect_to(course_lesson_path(@course, @lesson), alert: t("lessons.flash.no_questions_to_grade")) if @lesson.questions.empty?

    result = LessonQuizSubmissionService.new(lesson: @lesson, enrollment: enrollment, answers: answers).call
    progress = result[:progress]

    if result[:queued_ai_scoring]
      flash[:popup_title] = t("lessons.flash.answers_submitted_title")
      flash[:popup] = t("lessons.flash.answers_queued")
      redirect_to course_lesson_path(@course, @lesson, anchor: "lesson-status")
    else
      score = result[:score]
      flash[:popup_title] = t("lessons.flash.answers_submitted_title")
      flash[:popup] = t("lessons.flash.answers_scored",
                         score: score,
                         message: progress.completed? ? t("lessons.flash.lesson_marked_complete") : t("lessons.flash.keep_practising", pass_mark: @lesson.effective_pass_mark))
      redirect_to course_lesson_path(@course, @lesson, anchor: "lesson-status")
    end
  end

  def new
  end

  def create
    @lesson.course = @course
    @lesson.position ||= @course.lessons.maximum(:position).to_i + 1
    if assign_lesson_form_attributes && @lesson.save
      redirect_to course_lesson_path(@course, @lesson), notice: t("lessons.flash.created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    @lesson.cover_image.purge if ActiveModel::Type::Boolean.new.cast(params.dig(:lesson, :remove_cover_image))
    if assign_lesson_form_attributes && @lesson.save
      redirect_to course_lesson_path(@course, @lesson), notice: t("lessons.flash.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @lesson.destroy
    redirect_to course_path(@course), notice: t("lessons.flash.deleted"), status: :see_other
  end

  def publish
    @lesson.update(published_at: Time.current)
    redirect_to course_lesson_path(@course, @lesson), notice: t("lessons.flash.published")
  end

  def unpublish
    @lesson.update(published_at: nil)
    redirect_to course_lesson_path(@course, @lesson), notice: t("lessons.flash.unpublished")
  end

  def video_youtube_edit
  end

  def video_youtube_update
    @lesson.intro_video.purge if @lesson.intro_video.attached?
    if @lesson.update(params.require(:lesson).permit(:video_url))
      redirect_to edit_course_lesson_path(@course, @lesson), notice: t("lessons.flash.video_url_saved")
    else
      render :video_youtube_edit, status: :unprocessable_entity
    end
  end

  def video_upload_edit
  end

  def video_upload_update
    attrs = params.require(:lesson).permit(:intro_video)
    if attrs[:intro_video].blank?
      @lesson.errors.add(:intro_video, t("validation_messages.required"))
      return render :video_upload_edit, status: :unprocessable_entity
    end
    if @lesson.update(attrs.merge(video_url: nil))
      redirect_to edit_course_lesson_path(@course, @lesson), notice: t("lessons.flash.video_uploaded")
    else
      render :video_upload_edit, status: :unprocessable_entity
    end
  end

  def video_chatbar
    persist_lesson_video_attributes(:cbai_token, :cbai_api_key)
    fetch_video_data(:chatbar_recordings, :@recordings) if params[:fetch].present?
  end

  def video_synthesia
    persist_lesson_video_attributes(:synthesia_api_key)
    fetch_video_data(:synthesia_videos, :@synthesia_videos) if params[:fetch].present?
  end

  def video_heygen
    persist_lesson_video_attributes(:heygen_api_key)

    @heygen_video_id = params[:video_id].to_s.strip
    return unless params[:fetch].present?

    fetch_video_data(:heygen_video, :@heygen_video, video_id: params[:video_id]) do |result|
      @heygen_video_id = result[:video_id].to_s if result[:video_id].present?
    end
  end

  def import_recording
    result = video_import_service.import_chatbar_recording(recording_id: params[:recording_id])
    redirect_after_video_import(result, :video_chatbar_course_lesson_path)
  end

  def import_synthesia_video
    result = video_import_service.import_synthesia_video(video_id: params[:video_id])
    redirect_after_video_import(result, :video_synthesia_course_lesson_path)
  end

  def import_heygen_video
    result = video_import_service.import_heygen_video(video_id: params[:video_id])
    path_args = result[:type] == :import_failed ? { video_id: result[:video_id] } : {}
    redirect_after_video_import(result, :video_heygen_course_lesson_path, **path_args)
  end

  def destroy_video
    @lesson.intro_video.purge if @lesson.intro_video.attached?
    @lesson.update(video_url: nil)
    redirect_to edit_course_lesson_path(@course, @lesson), notice: t("lessons.flash.video_removed")
  end

  def poster_edit
  end

  def poster_update
    attrs = params.require(:lesson).permit(:poster_image)
    if attrs[:poster_image].blank?
      @lesson.errors.add(:poster_image, t("validation_messages.required"))
      return render :poster_edit, status: :unprocessable_entity
    end
    if @lesson.update(attrs)
      redirect_to edit_course_lesson_path(@course, @lesson), notice: t("lessons.flash.poster_saved")
    else
      render :poster_edit, status: :unprocessable_entity
    end
  end

  def destroy_poster
    @lesson.poster_image.purge if @lesson.poster_image.attached?
    redirect_to edit_course_lesson_path(@course, @lesson), notice: t("lessons.flash.poster_removed")
  end

  private

  def submission_answers
    answers_param = params[:answers]
    return answers_param.to_unsafe_h if answers_param.is_a?(ActionController::Parameters)

    answers_param || {}
  end

  def fail_scoring!(progress, enrollment, lesson)
    QuestionAnswer
      .joins(:question)
      .where(enrollment_id: enrollment.id, questions: { lesson_id: lesson.id, kind: Question.kinds[:free_text] })
      .where(ai_score: nil)
      .update_all(ai_score: 0, scored_at: Time.current)
    # Reuse the job's recalculation by running it inline — no pending answers remain so it skips straight to scoring
    LessonScoringJob.perform_now(progress.id)
  end

  def latest_quiz_answers_for(enrollment, lesson)
    QuestionAnswer
      .includes(:question)
      .joins(:question)
      .where(enrollment_id: enrollment.id, questions: { lesson_id: lesson.id })
      .order("questions.position")
      .to_a
  end

  def video_fetch_service
    @video_fetch_service ||= LessonVideoFetchService.new(lesson: @lesson)
  end

  def video_import_service
    @video_import_service ||= LessonVideoImportService.new(lesson: @lesson)
  end

  def persist_lesson_video_attributes(*attributes)
    return unless params[:lesson].present?

    @lesson.update(params.require(:lesson).permit(*attributes))
  end

  def fetch_video_data(fetch_method, instance_variable_name, **kwargs)
    result = video_fetch_service.public_send(fetch_method, **kwargs)
    yield result if block_given?

    if result[:ok]
      instance_variable_set(instance_variable_name, result[:data])
    else
      flash.now[:alert] = result[:error]
      instance_variable_set(instance_variable_name, nil)
    end
  end

  def redirect_after_video_import(result, fallback_path_helper, **path_args)
    return redirect_to(edit_course_lesson_path(@course, @lesson), notice: result[:notice]) if result[:ok]

    path_args[:fetch] = 1 if result[:type] == :import_failed
    path_args.compact!
    redirect_to public_send(fallback_path_helper, @course, @lesson, **path_args), alert: result[:error]
  end

  def set_course
    @course = Course.find_by(slug: params[:course_id]) || Course.find(params[:course_id])
  end

  def lesson_params
    params.require(:lesson).permit(*LessonFormAssignmentService::PERMITTED_ATTRIBUTES)
  end

  def assign_lesson_form_attributes
    LessonFormAssignmentService.new(lesson: @lesson, params: params).call
  end

  def fetch_anam_session_token
    AnamClient.new(api_key: @lesson.anam_api_key).session_token_for_persona(@lesson.anam_persona_id)
  rescue AnamClient::Error => e
    Rails.logger.warn("[ai-lms] Anam session token failed for lesson #{@lesson.id}: #{e.message}")
    nil
  end
end
