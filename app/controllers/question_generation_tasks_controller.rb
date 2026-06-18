class QuestionGenerationTasksController < ApplicationController
  before_action :authenticate_user!
  before_action :set_course_and_lesson
  before_action :authorize_generate!

  def create
    if @lesson.cbai_api_key.blank?
      redirect_to course_lesson_questions_path(@course, @lesson),
                  alert: "Set a ChatBar AI API key on this lesson first."
      return
    end

    @task = @lesson.question_generation_tasks.new(prompt: gen_params[:prompt].to_s.strip)
    unless @task.save
      redirect_to course_lesson_questions_path(@course, @lesson),
                  alert: "Could not create generation task: #{@task.errors.full_messages.to_sentence}"
      return
    end

    payload = build_task_payload(@task)

    begin
      response = CbaiClient.new(api_key: @lesson.cbai_api_key)
                           .create_task(payload: payload)
      @task.mark_queued!(cbai_task_id: response["id"].to_s, task_payload: payload)
      redirect_to course_lesson_questions_path(@course, @lesson),
                  notice: "Generation task queued. Questions will appear here when ChatBar AI responds."
    rescue CbaiClient::Error => e
      @task.mark_failed!(e.message)
      redirect_to course_lesson_questions_path(@course, @lesson),
                  alert: "ChatBar AI rejected the task: #{e.message}"
    end
  end

  def simulate
    raise ActionController::RoutingError, "Not available outside development" unless Rails.env.development?

    task = @lesson.question_generation_tasks.find(params[:id])
    return redirect_to course_lesson_questions_path(@course, @lesson),
                       alert: "Task already #{task.status}." unless task.pending? || task.queued?

    raw = params[:payload].to_s.strip
    payload =
      begin
        JSON.parse(raw)
      rescue JSON::ParserError => e
        return redirect_to course_lesson_questions_path(@course, @lesson),
                           alert: "[DEV] Invalid JSON: #{e.message}"
      end

    questions_data = extract_questions_from(payload)
    if questions_data.blank?
      return redirect_to course_lesson_questions_path(@course, @lesson),
                         alert: "[DEV] No questions found in payload. Check the JSON shape."
    end

    next_position = @lesson.questions.maximum(:position).to_i + 1
    created = 0
    questions_data.each do |q|
      next unless q.is_a?(Hash)
      prompt = q["prompt"].to_s.strip
      next if prompt.blank?

      kind = Question.kinds.key?(q["kind"].to_s) ? q["kind"].to_s : "free_text"
      question = @lesson.questions.new(
        prompt: prompt,
        kind: kind,
        correct_answer: q["correct_answer"].to_s,
        points: [ (q["points"] || 1).to_i, 0 ].max,
        position: next_position
      )
      question.choices_list = Array(q["choices"]).map(&:to_s)
      if question.save
        next_position += 1
        created += 1
      end
    end

    task.mark_succeeded!(response_payload: payload, questions_created_count: created)
    redirect_to course_lesson_questions_path(@course, @lesson),
                notice: "[DEV] Processed pasted payload: #{created} question(s) created."
  end

  private

  def extract_questions_from(payload)
    return payload if payload.is_a?(Array)

    candidate = payload["questions"] ||
                payload.dig("result", "questions") ||
                payload.dig("output", "questions") ||
                payload["output"] ||
                payload["result"]
    return candidate if candidate.is_a?(Array)

    summary = payload["summary"] || payload.dig("result", "summary")
    if summary.is_a?(String)
      begin
        parsed = JSON.parse(summary)
        return parsed["questions"] if parsed.is_a?(Hash) && parsed["questions"].is_a?(Array)
        return parsed if parsed.is_a?(Array)
      rescue JSON::ParserError
        nil
      end
    end

    nil
  end

  def set_course_and_lesson
    @course = Course.find_by(slug: params[:course_id]) || Course.find(params[:course_id])
    @lesson = @course.lessons.find(params[:lesson_id])
  end

  def authorize_generate!
    authorize! :manage, @lesson
  end

  def gen_params
    params.require(:question_generation_task).permit(:prompt, :count, :kind, :strategy)
  end

  def callback_url_overrides
    base = SiteSetting.current.app_url.presence ||
           ENV["CALLBACK_HOST"].to_s.strip.presence
    return {} if base.blank?

    uri = URI.parse(base.start_with?("http") ? base : "https://#{base}")
    overrides = { host: uri.host, protocol: uri.scheme || "https" }
    overrides[:port] = uri.port if uri.port && ![ 80, 443 ].include?(uri.port)
    overrides
  end

  def build_task_payload(task)
    count = gen_params[:count].to_i
    count = 5 if count <= 0
    count = 20 if count > 20

    kind = %w[multiple_choice true_false free_text mix].include?(gen_params[:kind]) ? gen_params[:kind] : "multiple_choice"
    strategy = %w[vector_similarity maximum_accuracy].include?(gen_params[:strategy]) ? gen_params[:strategy] : "vector_similarity"

    callback_url = unless Rails.env.development?
      api_question_generation_task_callback_url(
        token: task.callback_secret,
        **callback_url_overrides
      )
    end

    payload = {
      name: "LMS question generation · lesson #{@lesson.id} · #{Time.current.utc.iso8601}",
      strategy: strategy,
      description: helpers.question_generation_prompt(@lesson, focus: task.prompt, count: count, kind: kind)
    }
    payload[:callback_url] = callback_url if callback_url.present?
    payload
  end
end
