require "test_helper"

class LessonsControllerTest < ActionDispatch::IntegrationTest
  test "show published lesson anonymously" do
    get course_lesson_path(courses(:algebra), lessons(:intro))
    assert_response :success
  end

  test "lesson sidebar shows published lessons without exposing drafts" do
    get course_lesson_path(courses(:algebra), lessons(:intro))

    assert_response :success
    assert_select "#lesson-course-sidebar[aria-hidden='true']"
    assert_select "#lesson-course-sidebar [data-controller='lesson-accordion']"
    assert_select "#lesson-course-sidebar a[aria-current='page']", text: /Intro to Algebra/
    assert_select "#lesson-sidebar-details-#{lessons(:intro).id}:not(.hidden)"
    assert_select "#lesson-sidebar-details-#{lessons(:advanced).id}.hidden"
    assert_match "Quadratic equations", response.body
    assert_no_match "Draft Lesson", response.body
  end

  test "lesson sidebar shows draft lessons to the course owner" do
    sign_in users(:instructor)

    get course_lesson_path(courses(:algebra), lessons(:intro))

    assert_response :success
    assert_select "#lesson-course-sidebar", text: /Draft Lesson/
  end

  test "lesson sidebar progress ignores draft lessons like enrollment completion" do
    enrollment = enrollments(:student_in_algebra)
    Progress.find_or_initialize_by(enrollment: enrollment, lesson: lessons(:intro)).update!(status: :completed)
    Progress.find_or_initialize_by(enrollment: enrollment, lesson: lessons(:advanced)).update!(status: :completed)
    sign_in users(:student)

    get course_lesson_path(courses(:algebra), lessons(:intro))

    assert_response :success
    assert_select "#lesson-course-sidebar [role='progressbar'][aria-valuenow='100']"
    assert_equal 100.0, enrollment.completion_percentage
    assert enrollment.fully_completed?
  end

  test "show does not label incomplete quiz progress as completed" do
    progress = progresses(:student_intro)
    progress.update!(status: :not_started, completed_at: nil)
    sign_in users(:student)

    get course_lesson_path(courses(:algebra), lessons(:intro))

    assert_response :success
    assert_select "#lesson-status span.text-green-700", count: 0
  end

  test "show private course lesson redirects anonymous user" do
    get course_lesson_path(courses(:other_owner_course), lessons(:physics_lesson))
    assert_redirected_to root_path
  end

  test "show draft lesson denied for anonymous" do
    get course_lesson_path(courses(:algebra), lessons(:draft_lesson))
    assert_redirected_to root_path
  end

  test "owner can edit draft lesson" do
    sign_in users(:instructor)
    get edit_course_lesson_path(courses(:algebra), lessons(:draft_lesson))
    assert_response :success
  end

  test "non-owner cannot edit lesson" do
    sign_in users(:other_instructor)
    get edit_course_lesson_path(courses(:algebra), lessons(:intro))
    assert_redirected_to root_path
  end

  test "owner updates allow tutor provider and display mode" do
    sign_in users(:instructor)
    patch course_lesson_path(courses(:algebra), lessons(:intro)),
          params: { lesson: { title: "Renamed", ai_tutor_provider: "anam", cbai_display_mode: "none" } }
    assert_redirected_to course_lesson_path(courses(:algebra), lessons(:intro))
    assert_equal "none", lessons(:intro).reload.cbai_display_mode
    assert_equal "anam", lessons(:intro).reload.ai_tutor_provider
    assert_equal "Renamed", lessons(:intro).reload.title
  end

  test "owner can select the horizontal material scroller" do
    sign_in users(:instructor)

    patch course_lesson_path(courses(:algebra), lessons(:intro)),
          params: { lesson: { material_layout: "scroller" } }

    assert_redirected_to course_lesson_path(courses(:algebra), lessons(:intro))
    assert_equal "scroller", lessons(:intro).reload.material_layout
  end

  test "show renders material scroller controls when selected" do
    lesson = lessons(:intro)
    lesson.update!(material_layout: "scroller")
    lesson.lesson_materials.create!(title: "Reading", kind: :html, body: "Read this")

    get course_lesson_path(courses(:algebra), lesson)

    assert_response :success
    assert_select "[data-controller='material-scroller']", count: 1
    assert_select "button[data-action='material-scroller#next']", text: /Next/
  end

  test "instructor cannot configure a custom tutor script" do
    lesson = lessons(:intro)
    assert_nil lesson.custom_tutor_embed_script
    sign_in users(:instructor)

    patch course_lesson_path(courses(:algebra), lesson), params: {
      lesson: {
        ai_tutor_provider: "custom",
        custom_tutor_embed_type: "script",
        custom_tutor_embed_script: "<script>alert('unsafe')</script>"
      }
    }

    assert_response :unprocessable_entity
    assert_nil lesson.reload.custom_tutor_embed_script
  end

  test "admin can configure a custom tutor script" do
    lesson = lessons(:intro)
    sign_in users(:admin)

    patch course_lesson_path(courses(:algebra), lesson), params: {
      lesson: {
        ai_tutor_provider: "custom",
        custom_tutor_embed_type: "script",
        custom_tutor_embed_script: "<script src=\"https://trusted.example/widget.js\"></script>"
      }
    }

    assert_redirected_to course_lesson_path(courses(:algebra), lesson)
    lesson.reload
    assert_equal "script", lesson.custom_tutor_embed_type
    assert_equal "<script src=\"https://trusted.example/widget.js\"></script>", lesson.custom_tutor_embed_script
  end

  test "show hides ai tutor when display mode is none" do
    lessons(:intro).update!(cbai_display_mode: "none", cbai_token: "tok_intro")

    get course_lesson_path(courses(:algebra), lessons(:intro))

    assert_response :success
    assert_no_match "Open AI tutor", response.body
  end

  test "show renders anam avatar tutor when configured" do
    lessons(:intro).update!(
      ai_tutor_provider: "anam",
      anam_api_key: "anam-key",
      anam_persona_id: "persona-123",
      cbai_display_mode: "popup",
      cbai_token: nil
    )

    fake_client = Minitest::Mock.new
    fake_client.expect(:session_token_for_persona, "sess-token", [ "persona-123" ])

    AnamClient.stub(:new, fake_client) do
      get course_lesson_path(courses(:algebra), lessons(:intro))
    end

    fake_client.verify
    assert_response :success
    assert_match "Ask AI tutor", response.body
  end

  test "create with cbai api key syncs token from details endpoint" do
    sign_in users(:instructor)
    fake_client = Minitest::Mock.new
    fake_client.expect(:details, { "token" => "tok_from_details", "id" => 4242 })

    CbaiClient.stub(:new, fake_client) do
      post course_lessons_path(courses(:algebra)), params: {
        lesson: {
          title: "Lesson with AI",
          position: 9,
          body: "Body",
          cbai_api_key: "secret-key",
          cbai_display_mode: "popup"
        }
      }
    end

    fake_client.verify
    created = Lesson.order(:id).last
    assert_redirected_to course_lesson_path(courses(:algebra), created)
    assert_equal "secret-key", created.cbai_api_key
    assert_equal "tok_from_details", created.cbai_token
    assert_equal 4242, created.cbai_id
  end

  test "create assigns next position when submitted position is blank" do
    sign_in users(:instructor)

    assert_difference("Lesson.count", 1) do
      post course_lessons_path(courses(:algebra)), params: {
        lesson: {
          title: "Auto-positioned lesson",
          position: "",
          body: "Body"
        }
      }
    end

    created = Lesson.order(:id).last
    assert_redirected_to course_lesson_path(courses(:algebra), created)
    assert_equal 4, created.position
  end

  test "create with invalid cbai api key shows an error" do
    sign_in users(:instructor)

    CbaiClient.stub(:new, ->(*) { raise CbaiClient::Error, "unauthorized" }) do
      assert_no_difference("Lesson.count") do
        post course_lessons_path(courses(:algebra)), params: {
          lesson: {
            title: "Broken AI lesson",
            position: 9,
            body: "Body",
            cbai_api_key: "bad-key"
          }
        }
      end
    end

    assert_response :unprocessable_entity
    assert_match "could not load ChatBar AI details: unauthorized", response.body
  end

  test "lesson_params does not permit video_url" do
    sign_in users(:instructor)
    patch course_lesson_path(courses(:algebra), lessons(:intro)),
          params: { lesson: { title: "T", video_url: "https://example.com/x.mp4" } }
    assert_nil lessons(:intro).reload.video_url
  end

  test "update saves rich text body with links" do
    sign_in users(:instructor)
    html_body = '<p>Read the <a href="https://ruby-lang.org">Ruby docs</a>.</p>'

    patch course_lesson_path(courses(:algebra), lessons(:intro)),
          params: { lesson: { body: html_body } }

    assert_redirected_to course_lesson_path(courses(:algebra), lessons(:intro))
    assert_includes lessons(:intro).reload.body.to_s, 'href="https://ruby-lang.org"'

    get course_lesson_path(courses(:algebra), lessons(:intro))
    assert_response :success
    assert_match 'href="https://ruby-lang.org"', response.body
    assert_match "Ruby docs", response.body
  end

  test "video_youtube_update saves URL and purges any uploaded video" do
    sign_in users(:instructor)
    lessons(:intro).intro_video.attach(io: StringIO.new("x"), filename: "x.mp4", content_type: "video/mp4")
    patch video_youtube_course_lesson_path(courses(:algebra), lessons(:intro)),
          params: { lesson: { video_url: "https://www.youtube.com/watch?v=abc" } }
    assert_redirected_to edit_course_lesson_path(courses(:algebra), lessons(:intro))
    lessons(:intro).reload
    assert_equal "https://www.youtube.com/watch?v=abc", lessons(:intro).video_url
    assert_not lessons(:intro).intro_video.attached?
  end

  test "video_synthesia stores api key and lists videos" do
    sign_in users(:instructor)

    fake_client = Minitest::Mock.new
    fake_client.expect(:videos, [
      {
        "id" => "vid-123",
        "title" => "Welcome",
        "status" => "complete",
        "download" => "https://downloads.example.com/welcome.mp4"
      }
    ])

    SynthesiaClient.stub(:new, fake_client) do
      get video_synthesia_course_lesson_path(courses(:algebra), lessons(:intro)),
          params: { fetch: "1", lesson: { synthesia_api_key: "syn-key" } }
    end

    fake_client.verify
    assert_response :success
    assert_equal "syn-key", lessons(:intro).reload.synthesia_api_key
    assert_match "Available Synthesia videos", response.body
    assert_match "Welcome", response.body
  end

  test "import_synthesia_video attaches downloaded file and clears video_url" do
    sign_in users(:instructor)
    lessons(:intro).update!(synthesia_api_key: "syn-key", video_url: "https://example.com/old.mp4")

    fake_client = Minitest::Mock.new
    video = {
      "id" => "vid-123",
      "title" => "Synthesia welcome",
      "status" => "complete",
      "download" => "https://downloads.example.com/welcome.mp4"
    }
    fake_client.expect(:video, video, [ "vid-123" ])
    fake_client.expect(:download_video, nil) do |payload, &block|
      block.call(StringIO.new("video-data"), filename: "synthesia-welcome.mp4", content_type: "video/mp4")
      payload == video
    end

    SynthesiaClient.stub(:new, fake_client) do
      post import_synthesia_video_course_lesson_path(courses(:algebra), lessons(:intro), video_id: "vid-123")
    end

    fake_client.verify
    assert_redirected_to edit_course_lesson_path(courses(:algebra), lessons(:intro))
    lessons(:intro).reload
    assert_nil lessons(:intro).video_url
    assert lessons(:intro).intro_video.attached?
    assert_equal "synthesia-welcome.mp4", lessons(:intro).intro_video.filename.to_s
  end

  test "video_heygen stores api key and fetches a video by id" do
    sign_in users(:instructor)

    fake_client = Minitest::Mock.new
    fake_client.expect(:video, {
      "id" => "vid_abc123",
      "title" => "HeyGen welcome",
      "status" => "completed",
      "video_url" => "https://files.heygen.com/video/vid_abc123.mp4"
    }, [ "vid_abc123" ])

    HeygenClient.stub(:new, fake_client) do
      get video_heygen_course_lesson_path(courses(:algebra), lessons(:intro)),
          params: { fetch: "1", video_id: "vid_abc123", lesson: { heygen_api_key: "hey-key" } }
    end

    fake_client.verify
    assert_response :success
    assert_equal "hey-key", lessons(:intro).reload.heygen_api_key
    assert_match "HeyGen welcome", response.body
  end

  test "import_heygen_video attaches downloaded file and clears video_url" do
    sign_in users(:instructor)
    lessons(:intro).update!(heygen_api_key: "hey-key", video_url: "https://example.com/old.mp4")

    fake_client = Minitest::Mock.new
    video = {
      "id" => "vid_abc123",
      "title" => "HeyGen welcome",
      "status" => "completed",
      "video_url" => "https://files.heygen.com/video/vid_abc123.mp4"
    }
    fake_client.expect(:video, video, [ "vid_abc123" ])
    fake_client.expect(:download_video, nil) do |payload, &block|
      block.call(StringIO.new("video-data"), filename: "heygen-welcome.mp4", content_type: "video/mp4")
      payload == video
    end

    HeygenClient.stub(:new, fake_client) do
      post import_heygen_video_course_lesson_path(courses(:algebra), lessons(:intro), video_id: "vid_abc123")
    end

    fake_client.verify
    assert_redirected_to edit_course_lesson_path(courses(:algebra), lessons(:intro))
    lessons(:intro).reload
    assert_nil lessons(:intro).video_url
    assert lessons(:intro).intro_video.attached?
    assert_equal "heygen-welcome.mp4", lessons(:intro).intro_video.filename.to_s
  end

  test "destroy_video clears url and attachment" do
    sign_in users(:instructor)
    lessons(:intro).update!(video_url: "https://example.com/x.mp4")
    delete destroy_video_course_lesson_path(courses(:algebra), lessons(:intro))
    assert_redirected_to edit_course_lesson_path(courses(:algebra), lessons(:intro))
    assert_nil lessons(:intro).reload.video_url
  end

  test "poster_update attaches image and destroy_poster removes it" do
    sign_in users(:instructor)
    image = fixture_file_upload("poster.png", "image/png")
    patch poster_course_lesson_path(courses(:algebra), lessons(:intro)),
          params: { lesson: { poster_image: image } }
    assert lessons(:intro).reload.poster_image.attached?
    delete destroy_poster_course_lesson_path(courses(:algebra), lessons(:intro))
    assert_not lessons(:intro).reload.poster_image.attached?
  end

  test "publish and unpublish work for owner" do
    sign_in users(:instructor)
    post publish_course_lesson_path(courses(:algebra), lessons(:draft_lesson))
    assert lessons(:draft_lesson).reload.published?
    post unpublish_course_lesson_path(courses(:algebra), lessons(:draft_lesson))
    assert_not lessons(:draft_lesson).reload.published?
  end

  test "submit_quiz scores answers and updates progress" do
    sign_in users(:student)
    post submit_quiz_course_lesson_path(courses(:algebra), lessons(:intro)),
         params: { answers: { questions(:intro_q1).id.to_s => "2", questions(:intro_q2).id.to_s => "wrong" } }
    assert_redirected_to course_lesson_path(courses(:algebra), lessons(:intro), anchor: "lesson-status")
    enrollment = enrollments(:student_in_algebra)
    # Answers persisted
    qa1 = QuestionAnswer.find_by!(enrollment: enrollment, question: questions(:intro_q1))
    qa2 = QuestionAnswer.find_by!(enrollment: enrollment, question: questions(:intro_q2))
    assert_equal "2", qa1.answer_text
    assert_equal "wrong", qa2.answer_text
    # Score: 1 correct out of 2 equal-weighted MC questions = 50%
    progress = Progress.find_by!(enrollment: enrollment, lesson: lessons(:intro))
    assert_equal 50.0, progress.score.to_f
    assert progress.in_progress?
    assert_equal 1, progress.quiz_attempts.count
    assert_equal 50.0, progress.quiz_attempts.ordered.last.score.to_f
  end

  test "show displays latest marked quiz results for enrolled student" do
    sign_in users(:student)
    questions(:intro_q2).tap do |question|
      question.correct_answer = "matrix-only-answer"
      question.choices_list = [ "matrix-only-answer", "wrong" ]
      question.save!
    end

    post submit_quiz_course_lesson_path(courses(:algebra), lessons(:intro)),
         params: { answers: { questions(:intro_q1).id.to_s => "2", questions(:intro_q2).id.to_s => "wrong" } }

    get course_lesson_path(courses(:algebra), lessons(:intro))

    assert_response :success
    assert_match "Latest Quiz results", response.body
    assert_match 'id="quiz-results"', response.body
    assert_match 'data-controller="collapsible"', response.body
    assert_match 'data-expanded="false"', response.body
    assert_match 'data-collapsible-target="content"', response.body
    assert_match 'class="space-y-3 mt-4 hidden"', response.body
    assert_no_match "Question 1", response.body
    assert_no_match "Question 2", response.body
    assert_match "What is 1 + 1?", response.body
    assert_match "Correct", response.body
    assert_match "What is 2 + 2?", response.body
    assert_match "Incorrect", response.body
    assert_match "wrong", response.body
    assert_match "Correct answer", response.body
    assert_select "#quiz-results" do |elements|
      assert_no_match "matrix-only-answer", elements.first.to_html
    end
  end

  test "submit_quiz stores score for each attempt" do
    sign_in users(:student)

    post submit_quiz_course_lesson_path(courses(:algebra), lessons(:intro)),
         params: { answers: { questions(:intro_q1).id.to_s => "2", questions(:intro_q2).id.to_s => "wrong" } }
    post submit_quiz_course_lesson_path(courses(:algebra), lessons(:intro)),
         params: { answers: { questions(:intro_q1).id.to_s => "2", questions(:intro_q2).id.to_s => "4" } }

    progress = Progress.find_by!(enrollment: enrollments(:student_in_algebra), lesson: lessons(:intro))
    attempts = progress.quiz_attempts.ordered.to_a

    assert_equal 2, attempts.size
    assert_equal [ 1, 2 ], attempts.map(&:attempt_number)
    assert_equal [ 50.0, 100.0 ], attempts.map { |a| a.score.to_f }
  end

  test "student cannot submit quiz answers for an unpublished lesson" do
    sign_in users(:student)

    assert_no_difference("QuestionAnswer.count") do
      post submit_quiz_course_lesson_path(courses(:algebra), lessons(:draft_lesson)),
           params: { answers: {} }
    end

    assert_redirected_to root_path
  end

  test "submit_quiz enqueues LessonScoringJob when lesson has free-text questions and a CBAI key" do
    sign_in users(:student)
    lessons(:intro).update!(cbai_api_key: "test-key")
    questions(:intro_q1).update!(kind: :free_text)

    freeze_time do
      assert_enqueued_with(job: LessonScoringJob) do
        post submit_quiz_course_lesson_path(courses(:algebra), lessons(:intro)),
             params: { answers: { questions(:intro_q1).id.to_s => "my answer", questions(:intro_q2).id.to_s => "4" } }
      end

      assert_enqueued_with(job: ScoringCleanupJob, at: 10.minutes.from_now)
    end

    assert_enqueued_jobs 2, only: [ LessonScoringJob, ScoringCleanupJob ]

    assert_redirected_to course_lesson_path(courses(:algebra), lessons(:intro), anchor: "lesson-status")
    assert_match "AI", flash[:popup]

    progress = Progress.find_by!(enrollment: enrollments(:student_in_algebra), lesson: lessons(:intro))
    assert_nil progress.score
    attempt = progress.quiz_attempts.ordered.last
    assert_not_nil attempt
    assert attempt.pending?
    assert_nil attempt.score
  end

  test "submit_quiz with free-text and no CBAI key saves pending answers without scoring" do
    sign_in users(:student)
    lessons(:intro).update!(cbai_api_key: nil)
    questions(:intro_q1).update!(kind: :free_text)

    assert_no_enqueued_jobs(only: LessonScoringJob) do
      post submit_quiz_course_lesson_path(courses(:algebra), lessons(:intro)),
           params: { answers: { questions(:intro_q1).id.to_s => "my answer", questions(:intro_q2).id.to_s => "4" } }
    end

    assert_redirected_to course_lesson_path(courses(:algebra), lessons(:intro), anchor: "lesson-status")
    assert_match "instructor will be notified", flash[:popup_alert]
    assert_nil flash[:popup]

    progress = Progress.find_by!(enrollment: enrollments(:student_in_algebra), lesson: lessons(:intro))
    assert_nil progress.score
    assert progress.in_progress?

    attempt = progress.quiz_attempts.ordered.last
    assert_not_nil attempt
    assert attempt.pending?
    assert_nil attempt.score
  end
end
