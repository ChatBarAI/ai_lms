require "test_helper"
require "csv"

class Admin::UsersControllerTest < ActionDispatch::IntegrationTest
  test "non-admin is redirected" do
    sign_in users(:instructor)
    get admin_users_path
    assert_redirected_to root_path
  end

  test "admin can list users" do
    sign_in users(:admin)
    get admin_users_path
    assert_response :success
    assert_match "student@example.com", response.body
  end

  test "admin can filter by search term, role and organization" do
    sign_in users(:admin)
    users(:student).update!(organization: organizations(:acme))

    get admin_users_path(q: { email_or_name_cont: "student", role_eq: User.roles[:student], organization_id_eq: organizations(:acme).id })
    assert_response :success
    assert_match "student@example.com", response.body
    assert_no_match "instructor@example.com", response.body
  end

  test "admin can sort users (smoke test for each sort key)" do
    sign_in users(:admin)
    %w[email name last_sign_in_at role].each do |key|
      get admin_users_path(q: { s: "#{key} asc" })
      assert_response :success, "sort=#{key} failed"
    end
  end

  test "admin can view a user dossier" do
    sign_in users(:admin)
    get admin_user_path(users(:student))
    assert_response :success
    assert_match "student@example.com", response.body
  end

  test "admin can create a user" do
    sign_in users(:admin)
    assert_difference -> { User.count }, 1 do
      post admin_users_path, params: {
        user: { email: "new@example.com", name: "New", role: "student", password: generated_password }
      }
    end
  end

  test "admin can update a user without changing password when blank" do
    sign_in users(:admin)
    digest = users(:student).encrypted_password
    patch admin_user_path(users(:student)), params: { user: { name: "Renamed", password: "" } }
    assert_redirected_to admin_user_path(users(:student))
    assert_equal "Renamed", users(:student).reload.name
    assert_equal digest, users(:student).encrypted_password
  end

  test "admin cannot delete themselves" do
    sign_in users(:admin)
    assert_no_difference -> { User.count } do
      delete admin_user_path(users(:admin))
    end
    assert_redirected_to admin_users_path
  end

  test "admin can delete another user" do
    sign_in users(:admin)
    assert_difference -> { User.count }, -1 do
      delete admin_user_path(users(:other_student))
    end
  end

  test "admin can force-enrol a user in a course" do
    sign_in users(:admin)
    assert_difference -> { Enrollment.count }, 1 do
      post enroll_admin_user_path(users(:other_student)),
           params: { course_id: courses(:algebra).id }
    end
    assert_redirected_to admin_user_path(users(:other_student))
  end

  test "force-enrolment is idempotent" do
    sign_in users(:admin)
    assert_no_difference -> { Enrollment.count } do
      post enroll_admin_user_path(users(:student)),
           params: { course_id: courses(:algebra).id }
    end
  end

  test "admin can send a password reset email" do
    sign_in users(:admin)
    assert_emails 1 do
      post reset_password_admin_user_path(users(:student))
    end
    assert_redirected_to admin_user_path(users(:student))
  end

  test "admin can export users as CSV" do
    sign_in users(:admin)
    SiteSetting.current.update!(brand_name: "Acme Learning")

    student = users(:student)
    student.update!(
      sign_in_count: 7,
      last_sign_in_at: 2.days.ago,
      current_sign_in_ip: "203.0.113.10"
    )

    enrollment = enrollments(:student_in_algebra)
    intro_lesson = lessons(:intro)
    second_lesson = lessons(:advanced)
    third_lesson = lessons(:draft_lesson)

    Progress.find_or_create_by!(enrollment: enrollment, lesson: second_lesson) do |p|
      p.status = :completed
      p.score = 80
      p.updated_at = 1.day.ago
    end

    progresses(:student_intro).update!(status: :in_progress, score: 60, updated_at: 3.days.ago)

    not_started_progress = Progress.find_or_create_by!(enrollment: enrollment, lesson: third_lesson)
    not_started_progress.update!(status: :not_started, score: nil, updated_at: 4.days.ago)

    Certificate.find_or_create_by!(user: student, course: courses(:algebra))

    get export_admin_users_path(format: :csv)

    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_includes response.headers["Content-Disposition"], "acme-learning-users-#{Date.current}.csv"

    csv = CSV.parse(response.body, headers: true)
    headers = csv.headers

    assert_includes headers, "in_progress_lessons"
    assert_includes headers, "not_started_lessons"
    assert_includes headers, "total_lessons_attempted"
    assert_includes headers, "certificates_earned"
    assert_includes headers, "days_since_last_activity"
    assert_includes headers, "active_last_30_days"

    row = csv.find { |r| r["email"] == "student@example.com" }
    assert_not_nil row
    assert_equal "1", row["enrollments"]
    assert_equal "1", row["completed_lessons"]
    assert_equal "1", row["in_progress_lessons"]
    assert_equal "1", row["not_started_lessons"]
    assert_equal "3", row["total_lessons_attempted"]
    assert_equal "70.0", row["avg_score"]
    assert_equal "80.0", row["highest_score"]
    assert_equal "60.0", row["lowest_score"]
    assert_equal "1", row["certificates_earned"]
    assert_equal "1", row["ratings_given"]
    assert_equal "5.0", row["avg_rating_given"]
    assert_equal "7", row["sign_in_count"]
    assert_equal "203.0.113.10", row["current_sign_in_ip"]
    assert_equal "true", row["active_last_30_days"]
    assert row["last_sign_in_at"].present?
    assert row["last_activity_at"].present?
    assert row["created_at"].present?
  end

  test "export CSV respects filters" do
    sign_in users(:admin)

    get export_admin_users_path(format: :csv, q: { role_eq: User.roles[:instructor] })

    assert_response :success
    csv = CSV.parse(response.body, headers: true)

    assert csv.any?
    assert csv.all? { |r| r["role"] == "instructor" }
  end
end
