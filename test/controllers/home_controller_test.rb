require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "recent lessons exclude drafts future lessons and private guest courses" do
    lessons(:advanced).update!(published_at: 1.day.from_now)

    get root_path, params: { recent: "lessons" }

    assert_response :success
    assert_select "#recent-publications" do
      assert_select "a[aria-current=true]", text: "Lessons"
      assert_select "h3", text: "Intro to Algebra"
      assert_select "h3", text: "Quadratic equations", count: 0
      assert_select "h3", text: "Draft Lesson", count: 0
      assert_select "h3", text: "Newton's laws", count: 0
    end
  end

  test "recent subjects reflect visible course publication order" do
    sign_in users(:student)
    courses(:other_owner_course).update!(published_at: 1.hour.ago)

    get root_path, params: { recent: "subjects" }

    assert_response :success
    assert_select "#recent-publications h3" do |headings|
      assert_equal [ "Science", "Mathematics" ], headings.map(&:text)
    end

    sign_out users(:student)
    get root_path, params: { recent: "subjects" }
    assert_select "#recent-publications h3", text: "Mathematics"
    assert_select "#recent-publications h3", text: "Science", count: 0
  end

  test "recent filters respect course languages" do
    courses(:other_owner_course).update!(locale: "de")
    student = users(:student)
    student.update!(course_locales: [ "de" ])
    sign_in student

    get root_path, params: { recent: "lessons" }
    assert_select "#recent-publications h3", text: "Newton's laws"
    assert_select "#recent-publications h3", text: "Intro to Algebra", count: 0

    get root_path, params: { recent: "subjects" }
    assert_select "#recent-publications h3", text: "Science"
    assert_select "#recent-publications h3", text: "Mathematics", count: 0
  end

  test "disabled subjects and unknown recent filters fall back to courses" do
    SiteSetting.current.update!(subjects_enabled: false)

    %w[subjects unknown].each do |filter|
      get root_path, params: { recent: filter }
      assert_response :success
      assert_select "#recent-publications a[aria-current=true]", text: "Courses"
      assert_select "#recent-publications h3", text: "Algebra"
      assert_select "#recent-publications a", text: "Subjects", count: 0
    end
  end

  test "empty lesson filter keeps the pills available" do
    Lesson.update_all(published_at: nil)

    get root_path, params: { recent: "lessons" }

    assert_select "#recent-publications a[aria-current=true]", text: "Lessons"
    assert_select "#recent-publications p", text: "No published lessons yet."
  end

  test "renders root for anonymous user" do
    get root_path
    assert_response :success
    assert_select "html[lang=?]", "en"
    assert_match(/Browse subjects/, response.body)
    assert_match(/All courses/, response.body)
  end

  test "uses configured course terminology in public navigation and home actions" do
    setting = SiteSetting.current
    setting.update!(terminology: {
      "en" => {
        "course_one" => "Module",
        "course_other" => "Modules"
      }
    })

    get root_path

    assert_response :success
    assert_select "nav a", text: "Modules"
    assert_select "a", text: "All modules"
    assert_no_match(/>Courses</, response.body)
    assert_no_match(/>All courses</, response.body)
  ensure
    setting&.update!(terminology: {})
  end

  test "signed in German user sees German locale chrome" do
    student = users(:student)
    student.update!(locale: "de")
    sign_in student

    get profile_path

    assert_response :success
    assert_select "html[lang=?]", "de"
    assert_match(/Mein Profil/, response.body)
    assert_match(/Sprache: Deutsch/, response.body)
  end

  test "anonymous home page lists public recent courses only" do
    get root_path

    assert_response :success
    assert_match(/Algebra/, response.body)
    assert_no_match(/Physics 101/, response.body)
    assert_no_match(/Draft Course/, response.body)
  end

  test "anonymous home page hides recent section when no public courses are available" do
    Course.update_all(public_access_enabled: false)

    get root_path

    assert_response :success
    assert_no_match(/Recently published/, response.body)
    assert_no_match(/No published courses yet/, response.body)
  end

  test "signed in user sees published recent courses but not drafts" do
    sign_in users(:student)

    get root_path

    assert_response :success
    assert_match(/Algebra/, response.body)
    assert_no_match(/Draft Course/, response.body)
  end

  test "signed in student sees only recent items matching course languages" do
    courses(:algebra).update!(locale: "en")
    courses(:other_owner_course).update!(locale: "de")
    student = users(:student)
    student.update!(course_locales: [ "de" ])
    sign_in student

    get root_path

    assert_response :success
    assert_no_match(/Algebra/, response.body)
    assert_no_match(/Intro to Algebra/, response.body)
    assert_match(/Physics 101/, response.body)
  end

  test "signed in student does not see future-scheduled items" do
    sign_in users(:student)

    future_course = Course.create!(
      title: "Future Course",
      slug: "future-course",
      subject: subjects(:math),
      owner: users(:instructor),
      published_at: 2.days.from_now
    )

    Lesson.create!(
      course: future_course,
      title: "Future Lesson",
      position: 1,
      body: "Not yet live",
      published_at: 2.days.from_now
    )

    get root_path

    assert_response :success
    assert_no_match(/Future Course/, response.body)
    assert_no_match(/Future Lesson/, response.body)
  end
end
