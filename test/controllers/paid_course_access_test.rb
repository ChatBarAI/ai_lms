require "test_helper"

class PaidCourseAccessTest < ActionDispatch::IntegrationTest
  setup do
    @course = Course.create!(title: "Paid learning", owner: users(:instructor), published_at: 1.day.ago,
      public_access_enabled: true, access_policy: "entitlement_required", price_minor: 1000, price_currency: "eur")
    @lesson = @course.lessons.create!(title: "Public syllabus title", position: 1, published_at: 1.day.ago,
      body: "Public card preview. #{"Lesson description. " * 30}PRIVATE_LESSON_BODY", cbai_token: "private-token")
  end

  test "paid catalogue shows a bounded card preview without a lesson link or protected details" do
    get course_path(@course)
    assert_response :success
    assert_includes response.body, "Public syllabus title"
    assert_select "a:not([href])" do
      assert_select "h3", text: "1. Public syllabus title"
      assert_select "p.line-clamp-2", text: @lesson.body.to_plain_text.truncate(300)
    end
    assert_select "a[href=?]", course_lesson_path(@course, @lesson), count: 0
    assert_not_includes response.body, "PRIVATE_LESSON_BODY"
    assert_not_includes response.body, "private-token"
  end

  test "direct lessons token API and start reject unenitled learner" do
    sign_in users(:other_student)
    get course_lesson_path(@course, @lesson)
    assert_redirected_to root_path
    get api_lesson_path(@lesson.cbai_token), as: :json
    assert_response :forbidden
    assert_no_difference "Progress.count" do
      post start_course_lesson_path(@course, @lesson)
    end
    assert_redirected_to root_path
  end

  test "token API stays available to anonymous embeds for free courses and answers JSON when gated" do
    free = Course.create!(title: "Free private", owner: users(:instructor), published_at: nil, public_access_enabled: false)
    free_lesson = free.lessons.create!(title: "Draft lesson", position: 1, cbai_token: "free-embed-token")
    get api_lesson_path(free_lesson.cbai_token)
    assert_response :success
    assert_equal "Draft lesson", response.parsed_body["title"]
    get api_lesson_path(@lesson.cbai_token)
    assert_response :forbidden
    assert_equal "forbidden", response.parsed_body["error"]
  end

  test "withdrawal archives learning history and rejoin retains access" do
    user = users(:other_student)
    Entitlements::Grant.call(user: user, course: @course, source: "manual", reference: "manual",
      actor: users(:admin), reason: "Support")
    enrollment = Enrollment.create!(user: user, course: @course)
    progress = enrollment.progresses.create!(lesson: @lesson, status: :in_progress)
    sign_in user
    delete course_enrollment_path(@course, enrollment)
    assert enrollment.reload.archived_at
    assert progress.reload.persisted?
    post course_enrollments_path(@course)
    assert_nil enrollment.reload.archived_at
    get course_lesson_path(@course, @lesson)
    assert_response :success
  end

  test "public paid cover does not make course templates or learning blobs public" do
    @course.cover_image.attach(upload)
    @course.certificate_template.attach(upload)
    @lesson.poster_image.attach(upload)
    get rails_blob_path(@course.cover_image)
    assert_response :success
    get rails_blob_path(@course.certificate_template)
    assert_response :unauthorized
    get rails_blob_path(@lesson.poster_image)
    assert_response :unauthorized
    sign_in users(:other_student)
    get rails_blob_path(@lesson.poster_image)
    assert_response :forbidden
  end

  private

  def upload
    { io: File.open(Rails.root.join("test/fixtures/files/poster.png")), filename: "poster.png", content_type: "image/png" }
  end
end
