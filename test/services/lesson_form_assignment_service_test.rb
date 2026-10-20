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

    assert LessonFormAssignmentService.new(lesson: lesson, params: params, allow_custom_tutor_script: true).call

    assert_nil lesson.custom_tutor_embed_url
    assert_equal "<script src=\"https://example.com/widget.js\"></script>", lesson.custom_tutor_embed_script
  end

  test "rejects custom tutor scripts without administrator permission" do
    lesson = lessons(:intro)
    assert_nil lesson.custom_tutor_embed_script
    params = ActionController::Parameters.new(
      lesson: {
        ai_tutor_provider: "custom",
        custom_tutor_embed_type: "script",
        custom_tutor_embed_script: "<script>alert('unsafe')</script>"
      }
    )

    assert_not LessonFormAssignmentService.new(lesson: lesson, params: params).call
    assert_nil lesson.custom_tutor_embed_script
    assert_includes lesson.errors[:custom_tutor_embed_script], "can only be configured by an administrator"
  end

  test "preserves an admin-managed script during an unrelated instructor edit" do
    lesson = lessons(:intro)
    lesson.custom_tutor_embed_type = "script"
    lesson.custom_tutor_embed_script = "<script src=\"https://trusted.example/widget.js\"></script>"
    params = ActionController::Parameters.new(
      lesson: { title: "Instructor title update", ai_tutor_provider: "custom" }
    )

    assert LessonFormAssignmentService.new(lesson: lesson, params: params).call
    assert_equal "Instructor title update", lesson.title
    assert_equal "script", lesson.custom_tutor_embed_type
    assert_equal "<script src=\"https://trusted.example/widget.js\"></script>", lesson.custom_tutor_embed_script
  end

  test "blank secret fields keep the saved keys" do
    lesson = lessons(:intro)
    lesson.update!(cbai_api_key: "saved-cbai", anam_api_key: "saved-anam")
    params = ActionController::Parameters.new(lesson: { title: "Renamed", cbai_api_key: "", anam_api_key: "  " })

    CbaiClient.stub(:new, ->(*) { flunk "unchanged key should not be re-synced" }) do
      assert LessonFormAssignmentService.new(lesson: lesson, params: params).call
    end

    assert_equal "saved-cbai", lesson.cbai_api_key
    assert_equal "saved-anam", lesson.anam_api_key
  end

  test "verifies changed anam credentials" do
    lesson = lessons(:intro)
    params = ActionController::Parameters.new(lesson: { ai_tutor_provider: "anam", anam_api_key: "anam-key", anam_persona_id: "persona-1" })
    fake_client = Minitest::Mock.new
    fake_client.expect(:verify_persona!, true, [ "persona-1" ])

    AnamClient.stub(:new, fake_client) do
      assert LessonFormAssignmentService.new(lesson: lesson, params: params).call
    end

    fake_client.verify
  end

  test "rejects anam credentials the API does not accept" do
    lesson = lessons(:intro)
    params = ActionController::Parameters.new(lesson: { ai_tutor_provider: "anam", anam_api_key: "bad-key", anam_persona_id: "persona-1" })

    AnamClient.stub(:new, ->(**) { raise AnamClient::InvalidApiKey, "Anam rejected the API key" }) do
      assert_not LessonFormAssignmentService.new(lesson: lesson, params: params).call
    end
    assert_includes lesson.errors[:anam_api_key], "could not be verified: Anam rejected the API key"

    fake_client = Object.new
    def fake_client.verify_persona!(_) = raise(AnamClient::InvalidPersona, "Anam could not find that persona for this API key")
    AnamClient.stub(:new, fake_client) do
      assert_not LessonFormAssignmentService.new(lesson: lessons(:advanced), params: params).call
    end
    assert_includes lessons(:advanced).errors[:anam_persona_id], "could not be verified: Anam could not find that persona for this API key"
  end

  test "explains when the saved anam key is rejected after switching to anam" do
    lesson = lessons(:intro)
    lesson.update!(ai_tutor_provider: "chatbar", anam_api_key: "saved-anam", anam_persona_id: "persona-1")
    params = ActionController::Parameters.new(lesson: { ai_tutor_provider: "anam", anam_api_key: "" })

    AnamClient.stub(:new, ->(**) { raise AnamClient::InvalidApiKey, "Anam rejected the API key" }) do
      assert_not LessonFormAssignmentService.new(lesson: lesson, params: params).call
    end

    assert_equal "saved-anam", lesson.anam_api_key
    assert_includes lesson.errors[:anam_api_key],
      "saved for this lesson could not be verified: Anam rejected the API key. Enter a valid key, or choose another AI tutor provider"
  end

  test "requires both anam credentials when one is provided" do
    lesson = lessons(:intro)
    params = ActionController::Parameters.new(lesson: { ai_tutor_provider: "anam", anam_persona_id: "persona-1" })

    AnamClient.stub(:new, ->(**) { flunk "should not call Anam without a key" }) do
      assert_not LessonFormAssignmentService.new(lesson: lesson, params: params).call
    end
    assert_includes lesson.errors[:anam_api_key], "can't be blank when an Anam persona ID is set"
  end

  test "does not verify anam credentials when another tutor provider is selected" do
    lesson = lessons(:intro)
    params = ActionController::Parameters.new(lesson: { ai_tutor_provider: "none", anam_api_key: "anam-key" })

    AnamClient.stub(:new, ->(**) { flunk "should not call Anam" }) do
      assert LessonFormAssignmentService.new(lesson: lesson, params: params).call
    end
  end
end
