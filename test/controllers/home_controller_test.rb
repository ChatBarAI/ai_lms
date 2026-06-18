require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "renders root for anonymous user" do
    get root_path
    assert_response :success
    assert_match(/Mathematics/, response.body)
  end

  test "lists published courses but not drafts" do
    get root_path
    assert_match(/Algebra/, response.body)
    assert_no_match(/Draft Course/, response.body)
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
