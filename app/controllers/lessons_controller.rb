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
        @quiz_attempts = @progress.quiz_attempts.ordered.to_a
        @ai_scoring_pending = false
        flash.now[:alert] = "AI marking timed out after 5 minutes. Free-text answers have been scored as 0 — you can retake the #{helpers.terms[:quiz_l]}."
      end
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
      redirect_to course_lesson_path(@course, @lesson), alert: "Complete the required materials first." and return
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
    return redirect_to(course_lesson_path(@course, @lesson), alert: "Enrol to submit answers.") unless enrollment
    return redirect_to(course_lesson_path(@course, @lesson), alert: "Complete the required materials first.") unless @lesson.lesson_materials_complete_for?(enrollment)

    answers = submission_answers
    return redirect_to(course_lesson_path(@course, @lesson), alert: "No questions to grade.") if @lesson.questions.empty?

    result = LessonQuizSubmissionService.new(lesson: @lesson, enrollment: enrollment, answers: answers).call
    progress = result[:progress]

    if result[:queued_ai_scoring]
      flash[:popup_title] = "Answers submitted"
      flash[:popup] = "Your written responses are queued for marking by ChatBar AI. You can track progress in the Status section."
      redirect_to course_lesson_path(@course, @lesson, anchor: "lesson-status")
    else
      score = result[:score]
      flash[:popup_title] = "Answers submitted"
      flash[:popup] = "You scored #{score}%. #{progress.completed? ? 'Lesson marked complete.' : "Keep practising - pass mark is #{@lesson.effective_pass_mark}%."}"
      redirect_to course_lesson_path(@course, @lesson, anchor: "lesson-status")
    end
  end

  def new
  end

  def create
    @lesson.course = @course
    @lesson.position ||= @course.lessons.maximum(:position).to_i + 1
    if assign_lesson_form_attributes && @lesson.save
      redirect_to course_lesson_path(@course, @lesson), notice: "Lesson created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    @lesson.cover_image.purge if ActiveModel::Type::Boolean.new.cast(params.dig(:lesson, :remove_cover_image))
    if assign_lesson_form_attributes && @lesson.save
      redirect_to course_lesson_path(@course, @lesson), notice: "Lesson updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @lesson.destroy
    redirect_to course_path(@course), notice: "Lesson deleted.", status: :see_other
  end

  def publish
    @lesson.update(published_at: Time.current)
    redirect_to course_lesson_path(@course, @lesson), notice: "Lesson published."
  end

  def unpublish
    @lesson.update(published_at: nil)
    redirect_to course_lesson_path(@course, @lesson), notice: "Lesson unpublished."
  end

  def video_youtube_edit
  end

  def video_youtube_update
    @lesson.intro_video.purge if @lesson.intro_video.attached?
    if @lesson.update(params.require(:lesson).permit(:video_url))
      redirect_to edit_course_lesson_path(@course, @lesson), notice: "Video URL saved."
    else
      render :video_youtube_edit, status: :unprocessable_entity
    end
  end

  def video_upload_edit
  end

  def video_upload_update
    attrs = params.require(:lesson).permit(:intro_video)
    if attrs[:intro_video].blank?
      @lesson.errors.add(:intro_video, "is required")
      return render :video_upload_edit, status: :unprocessable_entity
    end
    if @lesson.update(attrs.merge(video_url: nil))
      redirect_to edit_course_lesson_path(@course, @lesson), notice: "Video uploaded."
    else
      render :video_upload_edit, status: :unprocessable_entity
    end
  end

  def video_chatbar
    if params[:lesson].present?
      @lesson.update(params.require(:lesson).permit(:cbai_token, :cbai_api_key))
    end
    return unless params[:fetch].present?

    result = video_fetch_service.chatbar_recordings
    if result[:ok]
      @recordings = result[:data]
    else
      flash.now[:alert] = result[:error]
      @recordings = nil
    end
  end

  def video_synthesia
    if params[:lesson].present?
      @lesson.update(params.require(:lesson).permit(:synthesia_api_key))
    end
    return unless params[:fetch].present?

    result = video_fetch_service.synthesia_videos
    if result[:ok]
      @synthesia_videos = result[:data]
    else
      flash.now[:alert] = result[:error]
      @synthesia_videos = nil
    end
  end

  def video_heygen
    if params[:lesson].present?
      @lesson.update(params.require(:lesson).permit(:heygen_api_key))
    end

    @heygen_video_id = params[:video_id].to_s.strip
    return unless params[:fetch].present?

    result = video_fetch_service.heygen_video(video_id: params[:video_id])
    @heygen_video_id = result[:video_id].to_s if result[:video_id].present?

    if result[:ok]
      @heygen_video = result[:data]
    else
      flash.now[:alert] = result[:error]
      @heygen_video = nil
    end
  end

  def import_recording
    result = video_import_service.import_chatbar_recording(recording_id: params[:recording_id])
    return redirect_to(edit_course_lesson_path(@course, @lesson), notice: result[:notice]) if result[:ok]

    path_args = {}
    path_args[:fetch] = 1 if result[:type] == :import_failed
    redirect_to video_chatbar_course_lesson_path(@course, @lesson, **path_args), alert: result[:error]
  end

  def import_synthesia_video
    result = video_import_service.import_synthesia_video(video_id: params[:video_id])
    return redirect_to(edit_course_lesson_path(@course, @lesson), notice: result[:notice]) if result[:ok]

    path_args = {}
    path_args[:fetch] = 1 if result[:type] == :import_failed
    redirect_to video_synthesia_course_lesson_path(@course, @lesson, **path_args), alert: result[:error]
  end

  def import_heygen_video
    result = video_import_service.import_heygen_video(video_id: params[:video_id])
    return redirect_to(edit_course_lesson_path(@course, @lesson), notice: result[:notice]) if result[:ok]

    path_args = {}
    if result[:type] == :import_failed
      path_args[:fetch] = 1
      path_args[:video_id] = result[:video_id]
    end
    redirect_to video_heygen_course_lesson_path(@course, @lesson, **path_args), alert: result[:error]
  end

  def destroy_video
    @lesson.intro_video.purge if @lesson.intro_video.attached?
    @lesson.update(video_url: nil)
    redirect_to edit_course_lesson_path(@course, @lesson), notice: "Intro video removed."
  end

  def poster_edit
  end

  def poster_update
    attrs = params.require(:lesson).permit(:poster_image)
    if attrs[:poster_image].blank?
      @lesson.errors.add(:poster_image, "is required")
      return render :poster_edit, status: :unprocessable_entity
    end
    if @lesson.update(attrs)
      redirect_to edit_course_lesson_path(@course, @lesson), notice: "Poster image saved."
    else
      render :poster_edit, status: :unprocessable_entity
    end
  end

  def destroy_poster
    @lesson.poster_image.purge if @lesson.poster_image.attached?
    redirect_to edit_course_lesson_path(@course, @lesson), notice: "Poster image removed."
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

  def video_fetch_service
    @video_fetch_service ||= LessonVideoFetchService.new(lesson: @lesson)
  end

  def video_import_service
    @video_import_service ||= LessonVideoImportService.new(lesson: @lesson)
  end

  def set_course
    @course = Course.find_by(slug: params[:course_id]) || Course.find(params[:course_id])
  end

  def lesson_params
    params.require(:lesson).permit(:title, :position, :body, :ai_tutor_provider, :cbai_display_mode, :custom_tutor_embed_url, :custom_tutor_embed_type, :custom_tutor_embed_script, :quiz_layout, :published_at, :pass_mark, :duration_minutes, :cover_image, :retry_incorrect_only, :ratings_enabled, :free_text_pass_level, tag_ids: [])
  end

  def assign_lesson_form_attributes
    attrs = lesson_params.to_h
    lesson_input = params.require(:lesson)

    if lesson_input.key?(:cbai_api_key)
      attrs["cbai_api_key"] = lesson_input[:cbai_api_key].to_s.strip.presence
    end

    if lesson_input.key?(:anam_api_key)
      attrs["anam_api_key"] = lesson_input[:anam_api_key].to_s.strip.presence
    end

    if lesson_input.key?(:anam_persona_id)
      attrs["anam_persona_id"] = lesson_input[:anam_persona_id].to_s.strip.presence
    end

    if lesson_input.key?(:custom_tutor_embed_url)
      attrs["custom_tutor_embed_url"] = lesson_input[:custom_tutor_embed_url].to_s.strip.presence
    end

    if lesson_input.key?(:custom_tutor_embed_script)
      attrs["custom_tutor_embed_script"] = lesson_input[:custom_tutor_embed_script].to_s.strip.presence
    end

    if attrs["ai_tutor_provider"] == "custom"
      if attrs["custom_tutor_embed_type"] == "script"
        attrs["custom_tutor_embed_url"] = nil
      else
        attrs["custom_tutor_embed_script"] = nil
      end
    end

    @lesson.assign_attributes(attrs)

    return true unless attrs.key?("cbai_api_key") && attrs["cbai_api_key"].present?

    details = CbaiClient.new(api_key: attrs["cbai_api_key"]).details
    @lesson.cbai_token = extract_cbai_token(details)
    @lesson.cbai_id = extract_cbai_id(details)
    true
  rescue CbaiClient::Error => e
    @lesson.errors.add(:cbai_api_key, "could not load ChatBar AI details: #{e.message}")
    false
  end

  def extract_cbai_token(details)
    token = details["token"].presence || details["cbai_token"].presence || details.dig("cbai", "token").presence
    raise CbaiClient::Error, "CBAI details did not include a token" if token.blank?

    token
  end

  def extract_cbai_id(details)
    raw = details["id"] || details["cbai_id"] || details.dig("cbai", "id")
    Integer(raw) if raw.present?
  rescue ArgumentError, TypeError
    nil
  end

  def fetch_anam_session_token
    AnamClient.new(api_key: @lesson.anam_api_key).session_token_for_persona(@lesson.anam_persona_id)
  rescue AnamClient::Error => e
    Rails.logger.warn("[ai-lms] Anam session token failed for lesson #{@lesson.id}: #{e.message}")
    nil
  end
end
