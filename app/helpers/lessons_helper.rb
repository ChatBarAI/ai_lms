module LessonsHelper
  def lesson_progress_ring(progress, classes: nil)
    pct = progress.completed? ? 100 : 50
    circ = (2 * Math::PI * 20).round(2)
    offset = (circ * (1 - pct / 100.0)).round(2)
    ring_color = progress.completed? ? "#16a34a" : "#6366f1"

    tag.svg(class: classes, width: "52", height: "52", viewBox: "0 0 48 48", fill: "none") do
      safe_join([
        tag.circle(cx: "24", cy: "24", r: "20", stroke: "#e5e7eb", "stroke-width": "4", fill: "none"),
        tag.circle(cx: "24", cy: "24", r: "20", stroke: ring_color, "stroke-width": "4", fill: "none", "stroke-dasharray": circ.to_s, "stroke-dashoffset": offset.to_s, "stroke-linecap": "round", transform: "rotate(-90 24 24)"),
        tag.text("#{pct}%", x: "24", y: "24", "text-anchor": "middle", "dominant-baseline": "central", "font-size": "10", fill: ring_color, "font-weight": "600")
      ])
    end
  end

  # Returns a hash describing the lesson's current intro video, or nil if none.
  def lesson_current_video_summary(lesson)
    if lesson.intro_video.attached?
      {
        label: "Uploaded file",
        detail: "#{lesson.intro_video.filename} (#{number_to_human_size(lesson.intro_video.byte_size)})"
      }
    elsif lesson.video_url.present?
      {
        label: "External URL",
        detail: lesson.video_url
      }
    end
  end

  # Returns an HTML-safe <iframe> or <video> tag for the given URL, or nil if blank/unrecognized.
  # If poster_url is given, an iframe-based embed is rendered as a click-to-play thumbnail and
  # a direct video URL gets the poster attribute.
  def lesson_video_embed(url, poster_url: nil)
    return nil if url.blank?

    uri = begin
      URI.parse(url.strip)
    rescue URI::InvalidURIError
      return nil
    end
    return nil unless uri.host

    host = uri.host.sub(/\Awww\./, "").downcase

    embed_src =
      case host
      when "youtube.com", "m.youtube.com"
        vid = Rack::Utils.parse_query(uri.query.to_s)["v"]
        vid.present? ? "https://www.youtube.com/embed/#{vid}?enablejsapi=1" : nil
      when "youtu.be"
        vid = uri.path.delete_prefix("/")
        vid.present? ? "https://www.youtube.com/embed/#{vid}?enablejsapi=1" : nil
      when "youtube-nocookie.com"
        url
      when "vimeo.com"
        vid = uri.path.delete_prefix("/").split("/").first
        vid.present? ? "https://player.vimeo.com/video/#{vid}" : nil
      when "player.vimeo.com"
        url
      end

    if embed_src
      if poster_url.present?
        iframe_src = embed_src + (embed_src.include?("?") ? "&" : "?") + "autoplay=1"
        render_click_to_play_iframe(iframe_src, poster_url)
      else
        content_tag(:div, class: "relative w-full mb-6", style: "padding-top:56.25%") do
          tag.iframe(
            src: embed_src,
            class: "absolute inset-0 w-full h-full rounded-lg border border-gray-200",
            allow: "accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture",
            allowfullscreen: true,
            loading: "lazy"
          )
        end
      end
    elsif url.match?(/\.(mp4|webm|ogg)\z/i)
      video_attrs = { controls: true, class: "w-full mb-6 rounded-lg border border-gray-200" }
      video_attrs[:poster] = poster_url if poster_url.present?
      content_tag(:video, video_attrs) do
        tag.source(src: url)
      end
    end
  end

  PROMPT_BODY_CHAR_LIMIT = 8_000

  #
  # Single source of truth for the AI question-generation prompt. Prompt
  # text could perhaps go in a prompt files directory, especially if we
  # add further prompts.
  #
  # Called with no keyword args to produce the UI preview (placeholders shown);
  # called with real values by the controller when building the actual task payload.
  #
  def question_generation_prompt(lesson, focus: nil, count: nil, kind: nil)
    body = strip_tags(lesson.body.to_s).squish
    body_section =
      if body.blank?
        "(no lesson body provided — rely on indexed lesson materials)"
      elsif body.length > PROMPT_BODY_CHAR_LIMIT
        "#{body[0, PROMPT_BODY_CHAR_LIMIT]}…[truncated]"
      else
        body
      end

    kind_instruction =
      case kind
      when "multiple_choice" then "Each question must be a multiple-choice question with 4 plausible options; exactly one correct."
      when "true_false"      then "Each question must be a true/false question. `choices` must be [\"True\", \"False\"] and `correct_answer` must be \"True\" or \"False\"."
      when "free_text"       then "Each question must be a short-answer / free-text question. Omit `choices`; put the model answer in `correct_answer`."
      when nil               then "{kind_instruction — depends on Question kind selected}"
      else                        "Mix kinds across multiple_choice, true_false, and free_text as appropriate."
      end

    focus_line =
      if focus.nil?
        "Instructor focus: {focus — from form, blank = cover broadly}"
      elsif focus.present?
        "Instructor focus: #{focus}"
      else
        "Instructor focus: (none — cover the lesson broadly)"
      end

    count_str = count.nil? ? "{count}" : count.to_s

    <<~PROMPT
      You are an expert lesson planner. Generate quiz questions based ONLY on the
      SOURCE MATERIAL that is appended after the final marker line at the very
      bottom of this prompt.

      === LESSON METADATA (context only — NEVER a source for questions) ===
      Title: #{lesson.title}
      Description: #{body_section}
      === END METADATA ===

      IMPORTANT — READ CAREFULLY:
      - The Lesson Title and Description above is METADATA ONLY. It exists to give you context.
        You MUST NOT write any questions based solely on the title.
      - The ONLY text you may use to write questions is the SOURCE MATERIAL that
        appears below the final marker line at the bottom of this prompt.
      - Every question and every correct answer MUST be verifiable from the
        appended SOURCE MATERIAL.

      #{focus_line}

      TASK:
      Generate exactly #{count_str} questions answerable from the appended SOURCE MATERIAL.
      #{kind_instruction}

      Rules:
      - `correct_answer` MUST be the exact text of the correct choice (not an index) for multiple_choice and true_false.
      - `points` is a non-negative integer (default 1).
      - `explanation` is a short (≤2 sentence) rationale shown to the learner after answering.

      Output format — respond with ONLY a single JSON object, no prose, no
      markdown fences, in this exact shape:

      {
        "questions": [
          {
            "prompt": "string — the question text",
            "kind": "multiple_choice" | "true_false" | "free_text",
            "choices": ["string", "..."],
            "correct_answer": "string",
            "points": 1,
            "explanation": "string"
          }
        ]
      }

      Everything below this line is the SOURCE MATERIAL. Use ONLY this text to
      write the questions. Ignore the metadata above.
      ===================== SOURCE MATERIAL BEGINS BELOW =====================
    PROMPT
  end

  def question_generation_prompt_preview(lesson)
    question_generation_prompt(lesson)
  end

  def quiz_answer_result(answer, lesson)
    question = answer.question

    if question.free_text?
      return result_descriptor("Pending", "bg-amber-50 text-amber-700 border-amber-200") if answer.ai_score.blank?

      if answer.ai_score >= lesson.free_text_pass_level
        result_descriptor("Marked #{answer.ai_score}/10", "bg-green-50 text-green-700 border-green-200")
      else
        result_descriptor("Marked #{answer.ai_score}/10", "bg-amber-50 text-amber-700 border-amber-200")
      end
    elsif answer.answer_text.to_s.strip.casecmp?(question.correct_answer.to_s.strip)
      result_descriptor("Correct", "bg-green-50 text-green-700 border-green-200")
    else
      result_descriptor("Incorrect", "bg-red-50 text-red-700 border-red-200")
    end
  end

  def quiz_answer_correct?(answer, lesson)
    question = answer.question

    if question.free_text?
      answer.ai_score.present? && answer.ai_score >= lesson.free_text_pass_level
    else
      answer.answer_text.to_s.strip.casecmp?(question.correct_answer.to_s.strip)
    end
  end

  private

  def result_descriptor(label, classes)
    { label: label, classes: classes }
  end

  def render_click_to_play_iframe(iframe_src, poster_url)
    content_tag(:div,
                class: "relative w-full mb-6 group cursor-pointer",
                style: "padding-top:56.25%",
                data: { lesson_video_poster: "1", iframe_src: iframe_src }) do
      img = image_tag(poster_url, class: "absolute inset-0 w-full h-full object-cover rounded-lg border border-gray-200", alt: "Video poster")
      overlay = content_tag(:div, class: "absolute inset-0 flex items-center justify-center") do
        content_tag(:div, "▶", class: "flex items-center justify-center w-16 h-16 rounded-full bg-black bg-opacity-60 text-white text-2xl group-hover:bg-opacity-80")
      end
      safe_join([ img, overlay ])
    end
  end
end
