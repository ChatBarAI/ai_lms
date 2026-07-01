require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "renders root for anonymous user" do
    get root_path
    assert_response :success
    assert_select "html[lang=?]", "en"
    assert_match(/Browse subjects/, response.body)
    assert_match(/All courses/, response.body)
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
