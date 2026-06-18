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
          params: { rating: { stars: 3 } }
    assert_equal 3, ratings(:student_intro_rating).reload.stars
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
