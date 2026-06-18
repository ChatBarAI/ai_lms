require "test_helper"

class CoursesControllerTest < ActionDispatch::IntegrationTest
  test "index lists published courses anonymously" do
    get courses_path
    assert_response :success
    assert_match(/Algebra/, response.body)
  end

  test "show published course anonymously" do
    get course_path(courses(:algebra))
    assert_response :success
  end

  test "show draft course redirects anonymous user" do
    get course_path(courses(:draft_course))
    assert_redirected_to root_path
  end

  test "show draft course allowed for owner" do
    sign_in users(:instructor)
    get course_path(courses(:draft_course))
    assert_response :success
  end

  test "show draft course denied for other instructor" do
    sign_in users(:other_instructor)
    get course_path(courses(:draft_course))
    assert_redirected_to root_path
  end

  test "new requires authentication" do
    get new_course_path
    assert_redirected_to new_user_session_path
  end

  test "instructor can create their own course" do
    sign_in users(:instructor)
    assert_difference -> { Course.count }, 1 do
      post courses_path, params: { course: { title: "Brand New", subject_id: subjects(:math).id, description: "x" } }
    end
    assert_redirected_to Course.last
    assert_equal users(:instructor), Course.last.owner
  end

  test "student cannot create a course" do
    sign_in users(:student)
    assert_no_difference -> { Course.count } do
      post courses_path, params: { course: { title: "Nope", subject_id: subjects(:math).id } }
    end
  end

  test "owner can update their own course" do
    sign_in users(:instructor)
    patch course_path(courses(:algebra)), params: { course: { description: "Updated" } }
    assert_redirected_to courses(:algebra)
    assert_equal "Updated", courses(:algebra).reload.description
  end

  test "owner sees lessons and add lesson action on edit page" do
    sign_in users(:instructor)

    get edit_course_path(courses(:algebra))

    assert_response :success
    assert_match "Lessons in this course", response.body
    assert_match "Intro to Algebra", response.body
    assert_match "Quadratic equations", response.body
    assert_match "Add lesson", response.body
  end

  test "non-owner cannot update another instructor's course" do
    sign_in users(:instructor)
    patch course_path(courses(:other_owner_course)), params: { course: { description: "Hacked" } }
    assert_redirected_to root_path
    assert_not_equal "Hacked", courses(:other_owner_course).reload.description
  end

  test "admin can publish and unpublish a course" do
    sign_in users(:admin)
    post publish_course_path(courses(:draft_course))
    assert courses(:draft_course).reload.published?
    post unpublish_course_path(courses(:draft_course))
    assert_not courses(:draft_course).reload.published?
  end

  test "owner can publish and unpublish their own course" do
    sign_in users(:instructor)
    post publish_course_path(courses(:draft_course))
    assert courses(:draft_course).reload.published?
    post unpublish_course_path(courses(:draft_course))
    assert_not courses(:draft_course).reload.published?
  end
end
