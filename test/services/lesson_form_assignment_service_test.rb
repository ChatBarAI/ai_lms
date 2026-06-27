require "test_helper"

class LessonFormAssignmentServiceTest < ActiveSupport::TestCase
  test "assigns normalized attributes and syncs cbai details" do
    lesson = lessons(:intro)
    params = ActionController::Parameters.new(
      lesson: {
        title: "Updated intro",
        cbai_api_key: " secret-key ",
        anam_api_key: " anam-key ",
        custom_tutor_embed_url: " https://example.com/tutor ",
        video_url: "https://example.com/ignored.mp4"
      }
    )
    fake_client = Minitest::Mock.new
    fake_client.expect(:details, { "token" => "tok_from_details", "id" => "42" })

    CbaiClient.stub(:new, fake_client) do
      assert LessonFormAssignmentService.new(lesson: lesson, params: params).call
    end

    fake_client.verify
    assert_equal "Updated intro", lesson.title
    assert_equal "secret-key", lesson.cbai_api_key
    assert_equal "anam-key", lesson.anam_api_key
    assert_equal "https://example.com/tutor", lesson.custom_tutor_embed_url
    assert_equal "tok_from_details", lesson.cbai_token
    assert_equal 42, lesson.cbai_id
    assert_nil lesson.video_url
  end

  test "adds cbai api key error when details sync fails" do
    lesson = lessons(:intro)
    params = ActionController::Parameters.new(lesson: { cbai_api_key: "bad-key" })

    CbaiClient.stub(:new, ->(*) { raise CbaiClient::Error, "unauthorized" }) do
      assert_not LessonFormAssignmentService.new(lesson: lesson, params: params).call
    end

    assert_includes lesson.errors[:cbai_api_key], "could not load ChatBar AI details: unauthorized"
  end

  test "clears inactive custom tutor embed field" do
    lesson = lessons(:intro)
    params = ActionController::Parameters.new(
      lesson: {
        ai_tutor_provider: "custom",
        custom_tutor_embed_type: "script",
        custom_tutor_embed_url: "https://example.com/tutor",
        custom_tutor_embed_script: " <script src=\"https://example.com/widget.js\"></script> "
      }
    )

    assert LessonFormAssignmentService.new(lesson: lesson, params: params).call

    assert_nil lesson.custom_tutor_embed_url
    assert_equal "<script src=\"https://example.com/widget.js\"></script>", lesson.custom_tutor_embed_script
  end
end
