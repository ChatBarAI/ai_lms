require "test_helper"

class RatingsControllerTest < ActionDispatch::IntegrationTest
  test "create requires auth" do
    post course_lesson_ratings_path(courses(:algebra), lessons(:intro)), params: { rating: { stars: 5 } }
    assert_redirected_to new_user_session_path
  end

  test "student can create a rating" do
    sign_in users(:other_student)
    assert_difference -> { Rating.count }, 1 do
      post course_lesson_ratings_path(courses(:algebra), lessons(:intro)), params: { rating: { stars: 4, comment: "Nice" } }
    end
    assert_redirected_to course_lesson_path(courses(:algebra), lessons(:intro))
  end

  test "student can create a comment-only rating" do
    sign_in users(:other_student)
    assert_difference -> { Rating.count }, 1 do
      post course_lesson_ratings_path(courses(:algebra), lessons(:intro)), params: { rating: { stars: nil, comment: "Helpful lesson" } }
    end
    assert_redirected_to course_lesson_path(courses(:algebra), lessons(:intro))
    assert_nil Rating.order(:id).last.stars
  end

  test "student can update their own rating" do
    sign_in users(:student)
    patch course_lesson_rating_path(courses(:algebra), lessons(:intro), ratings(:student_intro_rating)),
          params: { rating: { stars: 3, comment: "Updated feedback" } }
    assert_redirected_to course_lesson_path(courses(:algebra), lessons(:intro))
    assert_equal 3, ratings(:student_intro_rating).reload.stars
    assert_equal "Updated feedback", ratings(:student_intro_rating).comment
  end

  test "existing rating renders separate update and remove forms" do
    progresses(:student_intro).update!(status: :completed)
    sign_in users(:student)

    get course_lesson_path(courses(:algebra), lessons(:intro))

    assert_response :success
    rating_path = course_lesson_rating_path(courses(:algebra), lessons(:intro), ratings(:student_intro_rating))
    assert_select "form[action=?]", rating_path, count: 2 do |forms|
      update_form = forms.find { |form| form.at_css("input[name='_method'][value='patch']") }
      assert update_form, "Expected a form for updating the rating"
      assert_select update_form, "input[name='_method']", count: 1
      assert_select update_form, "select[name='rating[stars]']", count: 1
      assert_select update_form, "textarea[name='rating[comment]']", count: 1
      assert_select update_form, "input[type='submit'][value='Update rating']", count: 1

      remove_form = forms.find { |form| form.at_css("input[name='_method'][value='delete']") }
      assert remove_form, "Expected a separate form for removing the rating"
      assert_empty remove_form.ancestors("form")
      assert_select remove_form, "button[type='submit']", text: "Remove rating"
    end
  end

  test "create is blocked when lesson ratings are disabled" do
    lessons(:intro).update!(ratings_enabled: false)
    sign_in users(:other_student)

    assert_no_difference -> { Rating.count } do
      post course_lesson_ratings_path(courses(:algebra), lessons(:intro)), params: { rating: { stars: 4, comment: "Nice" } }
    end

    assert_redirected_to course_lesson_path(courses(:algebra), lessons(:intro))
    assert_match "disabled", flash[:alert]
  end

  test "update is blocked when lesson ratings are disabled" do
    lessons(:intro).update!(ratings_enabled: false)
    sign_in users(:student)

    patch course_lesson_rating_path(courses(:algebra), lessons(:intro), ratings(:student_intro_rating)),
          params: { rating: { stars: 1 } }

    assert_redirected_to course_lesson_path(courses(:algebra), lessons(:intro))
    assert_match "disabled", flash[:alert]
    assert_equal 5, ratings(:student_intro_rating).reload.stars
  end

  test "student cannot delete another user's rating" do
    sign_in users(:other_student)
    delete course_lesson_rating_path(courses(:algebra), lessons(:intro), ratings(:student_intro_rating))
    assert_redirected_to root_path
    assert Rating.exists?(ratings(:student_intro_rating).id)
  end
end
