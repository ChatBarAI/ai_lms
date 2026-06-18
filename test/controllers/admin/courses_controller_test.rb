require "test_helper"
require "csv"

class Admin::CoursesControllerTest < ActionDispatch::IntegrationTest
  test "non-admin redirected away" do
    sign_in users(:instructor)
    get admin_courses_path
    assert_redirected_to root_path
  end

  test "admin can list courses" do
    sign_in users(:admin)
    get admin_courses_path
    assert_response :success
  end

  test "admin can filter courses by subject" do
    sign_in users(:admin)
    get admin_courses_path(subject_id: subjects(:math).id)

    assert_response :success
    assert_match "Filtered by subject: Mathematics", response.body
    assert_match "Algebra", response.body
    assert_match "Draft Course", response.body
    assert_no_match "Physics 101", response.body
  end

  test "admin update does not change slug even if slug param sent" do
    sign_in users(:admin)
    original = courses(:algebra).slug
    patch admin_course_path(courses(:algebra)), params: { course: { title: "Renamed", slug: "hacked-slug" } }
    courses(:algebra).reload
    assert_equal original, courses(:algebra).slug
    assert_equal "Renamed", courses(:algebra).title
  end

  test "admin can export courses as CSV" do
    sign_in users(:admin)
    SiteSetting.current.update!(brand_name: "Acme Learning")

    course = courses(:algebra)
    enrollment = enrollments(:student_in_algebra)

    progresses(:student_intro).update!(
      status: :completed,
      score: 85,
      completed_at: 1.day.ago,
      updated_at: 1.day.ago
    )

    Progress.find_or_create_by!(enrollment: enrollment, lesson: lessons(:advanced)) do |p|
      p.status = :in_progress
      p.score = 70
      p.updated_at = 2.days.ago
    end

    Rating.find_or_create_by!(user: users(:student), lesson: lessons(:advanced)) do |rating|
      rating.stars = 4
      rating.comment = "Good"
    end

    Certificate.find_or_create_by!(user: users(:student), course: course)

    get admin_courses_path(format: :csv)

    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_includes response.headers["Content-Disposition"], "acme-learning-courses-#{Date.current}.csv"

    csv = CSV.parse(response.body, headers: true)
    headers = csv.headers

    assert_includes headers, "total_lessons"
    assert_includes headers, "published_lessons"
    assert_includes headers, "active_learners"
    assert_includes headers, "completed_progresses"
    assert_includes headers, "in_progress_progresses"
    assert_includes headers, "not_started_progresses"
    assert_includes headers, "avg_score"
    assert_includes headers, "avg_rating"
    assert_includes headers, "certificates_issued"

    row = csv.find { |r| r["slug"] == "algebra" }
    assert_not_nil row
    assert_equal "Algebra", row["title"]
    assert_equal "Mathematics", row["subject"]
    assert_equal "instructor@example.com", row["owner_email"]
    assert_equal "published", row["status"]
    assert_equal "3", row["total_lessons"]
    assert_equal "2", row["published_lessons"]
    assert_equal "1", row["enrollments"]
    assert_equal "1", row["active_learners"]
    assert_equal "1", row["completed_progresses"]
    assert_equal "1", row["in_progress_progresses"]
    assert_equal "0", row["not_started_progresses"]
    assert_equal "2", row["total_progress_records"]
    assert_equal "77.5", row["avg_score"]
    assert_equal "4.5", row["avg_rating"]
    assert_equal "2", row["ratings_count"]
    assert_equal "1", row["certificates_issued"]
    assert row["last_enrollment_at"].present?
    assert row["last_completion_at"].present?
  end

  test "admin can export courses CSV filtered by subject" do
    sign_in users(:admin)

    get admin_courses_path(format: :csv, subject_id: subjects(:math).id)

    assert_response :success
    csv = CSV.parse(response.body, headers: true)

    assert csv.any?
    slugs = csv.map { |r| r["slug"] }
    assert_includes slugs, "algebra"
    assert_includes slugs, "draft-course"
    refute_includes slugs, "physics-101"
  end
end
