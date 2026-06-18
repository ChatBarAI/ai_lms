class LessonVideoFetchService
  def initialize(lesson:)
    @lesson = lesson
  end

  def chatbar_recordings
    return failure("CBAI API key is required to fetch recordings.") if @lesson.cbai_api_key.blank?

    success(CbaiClient.new(api_key: @lesson.cbai_api_key).recordings)
  rescue CbaiClient::Error => e
    failure("Could not fetch recordings: #{e.message}")
  end

  def synthesia_videos
    return failure("Synthesia API key is required to fetch videos.") if @lesson.synthesia_api_key.blank?

    success(SynthesiaClient.new(api_key: @lesson.synthesia_api_key).videos)
  rescue SynthesiaClient::Error => e
    failure("Could not fetch Synthesia videos: #{e.message}")
  end

  def heygen_video(video_id:)
    return failure("HeyGen API key is required to fetch a video.") if @lesson.heygen_api_key.blank?

    normalized_video_id = video_id.to_s.strip
    return failure("Video ID is required to fetch from HeyGen.", video_id: normalized_video_id) if normalized_video_id.blank?

    success(HeygenClient.new(api_key: @lesson.heygen_api_key).video(normalized_video_id), video_id: normalized_video_id)
  rescue HeygenClient::Error => e
    failure("Could not fetch HeyGen video: #{e.message}", video_id: normalized_video_id)
  end

  private

  def success(data, video_id: nil)
    { ok: true, data: data, error: nil, video_id: video_id }
  end

  def failure(error, video_id: nil)
    { ok: false, data: nil, error: error, video_id: video_id }
  end
end
