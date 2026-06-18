class LessonVideoImportService
  def initialize(lesson:)
    @lesson = lesson
  end

  def import_chatbar_recording(recording_id:)
    rid = recording_id.to_s
    return failure("Missing CBAI API key or recording id.", type: :missing_input) if @lesson.cbai_api_key.blank? || rid.blank?

    client = CbaiClient.new(api_key: @lesson.cbai_api_key)
    client.download_recording(rid) do |file|
      attach_intro_video(file, filename: "cbai-recording-#{rid}.webm", content_type: "video/webm")
    end

    clear_video_url!
    success("Recording imported as intro video.")
  rescue CbaiClient::Error => e
    failure("Import failed: #{e.message}", type: :import_failed)
  end

  def import_synthesia_video(video_id:)
    normalized_video_id = video_id.to_s
    return failure("Missing Synthesia API key or video id.", type: :missing_input) if @lesson.synthesia_api_key.blank? || normalized_video_id.blank?

    client = SynthesiaClient.new(api_key: @lesson.synthesia_api_key)
    video = client.video(normalized_video_id)

    client.download_video(video) do |file, filename:, content_type:|
      attach_intro_video(file, filename: filename, content_type: content_type)
    end

    clear_video_url!
    success("Synthesia video imported as intro video.")
  rescue SynthesiaClient::Error => e
    failure("Import failed: #{e.message}", type: :import_failed)
  end

  def import_heygen_video(video_id:)
    normalized_video_id = video_id.to_s
    return failure("Missing HeyGen API key or video id.", type: :missing_input, video_id: normalized_video_id) if @lesson.heygen_api_key.blank? || normalized_video_id.blank?

    client = HeygenClient.new(api_key: @lesson.heygen_api_key)
    video = client.video(normalized_video_id)

    client.download_video(video) do |file, filename:, content_type:|
      attach_intro_video(file, filename: filename, content_type: content_type)
    end

    clear_video_url!
    success("HeyGen video imported as intro video.")
  rescue HeygenClient::Error => e
    failure("Import failed: #{e.message}", type: :import_failed, video_id: normalized_video_id)
  end

  private

  def attach_intro_video(file, filename:, content_type:)
    @lesson.intro_video.attach(io: file, filename: filename, content_type: content_type)
  end

  def clear_video_url!
    @lesson.update(video_url: nil)
  end

  def success(notice, video_id: nil)
    { ok: true, notice: notice, error: nil, type: nil, video_id: video_id }
  end

  def failure(error, type:, video_id: nil)
    { ok: false, notice: nil, error: error, type: type, video_id: video_id }
  end
end
