require "test_helper"

class LessonTest < ActiveSupport::TestCase
  test "valid fixture" do
    assert lessons(:intro).valid?
  end

  test "requires title and position" do
    # title: course present so position is auto-assigned, but title is still required
    l = Lesson.new(course: courses(:algebra))
    assert_not l.valid?
    assert_includes l.errors[:title], "can't be blank"

    # position: no course so assign_position is skipped, exposing the validation
    l2 = Lesson.new(title: "X")
    assert_not l2.valid?
    assert_includes l2.errors[:position], "can't be blank"
  end

  test "position must be non-negative integer" do
    l = Lesson.new(course: courses(:algebra), title: "X", position: -1)
    assert_not l.valid?
  end

  test "published? checks published_at" do
    assert lessons(:intro).published?
    assert_not lessons(:draft_lesson).published?
  end

  test "published scope" do
    assert_includes Lesson.published, lessons(:intro)
    assert_not_includes Lesson.published, lessons(:draft_lesson)

    scheduled = Lesson.create!(
      course: courses(:algebra),
      title: "Scheduled Lesson",
      position: 99,
      published_at: 1.day.from_now
    )
    scheduled.body = "<p>Coming soon</p>"
    scheduled.save!

    assert_not scheduled.published?
    assert_not_includes Lesson.published, scheduled
  end

  test "body is ActionText rich text" do
    lesson = lessons(:intro)
    assert lesson.body.present?
    assert_includes lesson.body.to_s, "Welcome"
  end

  test "cbai_display_mode validates against allowed values" do
    l = lessons(:intro)
    l.cbai_display_mode = "weird"
    assert_not l.valid?
    %w[popup drawer none].each do |mode|
      l.cbai_display_mode = mode
      assert l.valid?, "expected #{mode} to be valid"
    end
    l.cbai_display_mode = nil
    assert l.valid?, "blank should be allowed"
  end

  test "cbai_display_mode_or_default falls back to popup" do
    l = lessons(:intro)
    l.cbai_display_mode = nil
    assert_equal "popup", l.cbai_display_mode_or_default
    l.cbai_display_mode = "drawer"
    assert_equal "drawer", l.cbai_display_mode_or_default
    l.cbai_display_mode = "none"
    assert_equal "none", l.cbai_display_mode_or_default
    l.cbai_display_mode = "garbage"
    assert_equal "popup", l.cbai_display_mode_or_default
  end

  test "ai_tutor_provider validates against allowed values" do
    l = lessons(:intro)
    l.ai_tutor_provider = "weird"
    assert_not l.valid?

    %w[chatbar anam none].each do |provider|
      l.ai_tutor_provider = provider
      assert l.valid?, "expected #{provider} to be valid"
    end

    l.ai_tutor_provider = nil
    assert l.valid?, "blank should be allowed"
  end

  test "ai_tutor_provider_or_default falls back to chatbar" do
    l = lessons(:intro)

    l.ai_tutor_provider = nil
    assert_equal "chatbar", l.ai_tutor_provider_or_default

    l.ai_tutor_provider = "anam"
    assert_equal "anam", l.ai_tutor_provider_or_default

    l.ai_tutor_provider = "none"
    assert_equal "none", l.ai_tutor_provider_or_default

    l.ai_tutor_provider = "garbage"
    assert_equal "chatbar", l.ai_tutor_provider_or_default
  end

  test "cbai_enabled? requires token and non-none display mode" do
    l = lessons(:intro)
    l.ai_tutor_provider = "chatbar"
    l.cbai_token = "tok"
    l.cbai_display_mode = "popup"
    assert l.cbai_enabled?

    l.cbai_display_mode = "none"
    assert_not l.cbai_enabled?

    l.cbai_token = nil
    l.cbai_display_mode = "popup"
    assert_not l.cbai_enabled?

    l.ai_tutor_provider = "anam"
    l.cbai_token = "tok"
    assert_not l.cbai_enabled?

    l.ai_tutor_provider = "none"
    l.cbai_token = "tok"
    assert_not l.cbai_enabled?
  end

  test "anam_enabled? requires provider, creds and non-none display mode" do
    l = lessons(:intro)
    l.ai_tutor_provider = "anam"
    l.anam_api_key = "anam-key"
    l.anam_persona_id = "persona-id"
    l.cbai_display_mode = "popup"
    assert l.anam_enabled?

    l.cbai_display_mode = "none"
    assert_not l.anam_enabled?

    l.cbai_display_mode = "popup"
    l.anam_persona_id = nil
    assert_not l.anam_enabled?

    l.anam_persona_id = "persona-id"
    l.ai_tutor_provider = "chatbar"
    assert_not l.anam_enabled?

    l.ai_tutor_provider = "none"
    assert_not l.anam_enabled?
  end

  test "average_rating computes from ratings" do
    assert_equal 5.0, lessons(:intro).average_rating.to_f
  end

  test "intro_video rejects non-video content types" do
    lesson = lessons(:intro)
    lesson.intro_video.attach(io: StringIO.new("x"), filename: "x.txt", content_type: "text/plain")
    assert_not lesson.valid?
    assert lesson.errors[:intro_video].any?
  end

  test "poster_image rejects non-image content types" do
    lesson = lessons(:intro)
    lesson.poster_image.attach(io: StringIO.new("x"), filename: "x.txt", content_type: "text/plain")
    assert_not lesson.valid?
    assert lesson.errors[:poster_image].any?
  end

  test "questions_for_submission returns only submitted questions in retry mode" do
    lesson = lessons(:intro)
    lesson.update!(retry_incorrect_only: true)

    result = lesson.questions_for_submission(submitted_answer_ids: [ questions(:intro_q1).id ])

    assert_equal [ questions(:intro_q1).id ], result.pluck(:id)
  end

  test "immediate_score_for uses stored answers for unsubmitted retry questions" do
    lesson = lessons(:intro)
    lesson.update!(retry_incorrect_only: true)
    enrollment = enrollments(:student_in_algebra)

    QuestionAnswer.create!(
      enrollment: enrollment,
      question: questions(:intro_q2),
      answer_text: "4"
    )

    score = lesson.immediate_score_for(
      enrollment: enrollment,
      answers: { questions(:intro_q1).id.to_s => "2" }
    )

    assert_equal 100.0, score
  end
end
