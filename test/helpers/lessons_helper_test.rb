require "test_helper"

class LessonsHelperTest < ActionView::TestCase
  test "returns nil for blank or unrecognized URLs" do
    assert_nil lesson_video_embed(nil)
    assert_nil lesson_video_embed("")
    assert_nil lesson_video_embed("not a url")
    assert_nil lesson_video_embed("https://example.com/page")
  end

  test "embeds youtube watch URLs as iframe" do
    html = lesson_video_embed("https://www.youtube.com/watch?v=abc123")
    assert_includes html, "iframe"
    assert_includes html, "youtube.com/embed/abc123"
  end

  test "embeds youtu.be short URLs as iframe" do
    html = lesson_video_embed("https://youtu.be/abc123")
    assert_includes html, "youtube.com/embed/abc123"
  end

  test "embeds vimeo URLs as iframe" do
    html = lesson_video_embed("https://vimeo.com/12345")
    assert_includes html, "player.vimeo.com/video/12345"
  end

  test "embeds direct mp4 as video tag" do
    html = lesson_video_embed("https://example.com/clip.mp4")
    assert_includes html, "<video"
    assert_includes html, "controls"
  end

  test "adds poster to video tag when poster_url given" do
    html = lesson_video_embed("https://example.com/clip.mp4", poster_url: "/poster.png")
    assert_includes html, 'poster="/poster.png"'
  end

  test "renders click-to-play wrapper for iframe when poster_url given" do
    html = lesson_video_embed("https://www.youtube.com/watch?v=abc123", poster_url: "/poster.png")
    assert_includes html, "data-lesson-video-poster"
    assert_includes html, "/poster.png"
    assert_includes html, "autoplay=1"
    # no iframe rendered until user clicks
    assert_not_includes html, "<iframe"
  end

  test "current video summary for uploaded video" do
    lesson = lessons(:intro)
    lesson.intro_video.attach(io: StringIO.new("x"), filename: "x.mp4", content_type: "video/mp4")
    summary = lesson_current_video_summary(lesson)
    assert_equal "Uploaded file", summary[:label]
  end

  test "current video summary for external URL" do
    lesson = lessons(:intro)
    lesson.update!(video_url: "https://example.com/x.mp4")
    summary = lesson_current_video_summary(lesson)
    assert_equal "External URL", summary[:label]
  end

  test "current video summary nil when no video" do
    assert_nil lesson_current_video_summary(lessons(:intro))
  end
end
