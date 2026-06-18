class Api::QuestionGenerationTasksController < ApplicationController
  skip_forgery_protection
  skip_before_action :allow_browser, raise: false
  skip_before_action :authenticate_user!, raise: false

  # POST /api/question_generation_tasks/:token/callback
  def callback
    task = QuestionGenerationTask.find_by(callback_secret: params[:token].to_s)
    return head :not_found if task.nil?

    if task.succeeded?
      return render json: { ok: true, already_processed: true }
    end

    payload = parse_payload
    questions_data = extract_questions(payload)

    if questions_data.blank?
      task.mark_failed!("The ChatBar AI Task did not generate any questions", response_payload: payload)
      return render json: { ok: false, error: "no questions in payload" }, status: :unprocessable_entity
    end

    created = create_questions(task.lesson, questions_data)
    task.mark_succeeded!(response_payload: payload, questions_created_count: created)
    notify_cbai_task_complete(task)
    render json: { ok: true, questions_created: created }
  rescue => e
    Rails.logger.error("[QuestionGenerationTask callback] #{e.class}: #{e.message}")
    task&.mark_failed!("#{e.class}: #{e.message}")
    render json: { ok: false, error: e.message }, status: :internal_server_error
  end

  private

  def parse_payload
    raw = request.body.read
    return {} if raw.blank?
    JSON.parse(raw)
  rescue JSON::ParserError
    { "raw" => raw.to_s[0, 4000] }
  end

  def extract_questions(payload)
    return payload if payload.is_a?(Array)

    candidate = payload["questions"] ||
                payload.dig("result", "questions") ||
                payload.dig("output", "questions") ||
                payload.dig("task", "questions") ||
                payload["output"] ||
                payload["result"]

    return candidate if candidate.is_a?(Array)

    summary = payload["summary"] ||
              payload.dig("result", "summary") ||
              payload.dig("task", "result") ||
              payload.dig("task", "summary")
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

  def create_questions(lesson, questions_data)
    next_position = lesson.questions.maximum(:position).to_i + 1
    created = 0

    questions_data.each do |q|
      next unless q.is_a?(Hash)
      prompt = q["prompt"].to_s.strip
      next if prompt.blank?

      kind = normalize_kind(q["kind"])
      choices = Array(q["choices"]).map(&:to_s)
      correct = q["correct_answer"].to_s
      points = (q["points"] || 1).to_i

      question = lesson.questions.new(
        prompt: prompt,
        kind: kind,
        correct_answer: correct,
        points: points >= 0 ? points : 1,
        position: next_position
      )
      question.choices_list = choices
      if question.save
        next_position += 1
        created += 1
      end
    end

    created
  end

  def normalize_kind(raw)
    Question.kinds.key?(raw.to_s) ? raw.to_s : "free_text"
  end

  def notify_cbai_task_complete(task)
    return if task.cbai_task_id.blank? || task.lesson.cbai_api_key.blank?

    CbaiClient.new(api_key: task.lesson.cbai_api_key)
              .update_task(cbai_task_id: task.cbai_task_id)
  rescue CbaiClient::Error => e
    Rails.logger.warn("[QuestionGenerationTask] Could not notify CBAI of task completion: #{e.message}")
  end
end
