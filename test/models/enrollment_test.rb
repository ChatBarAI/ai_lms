require "test_helper"

class EnrollmentTest < ActiveSupport::TestCase
  test "valid fixture" do
    assert enrollments(:student_in_algebra).valid?
  end

  test "user+course must be unique" do
    dup = Enrollment.new(user: users(:student), course: courses(:algebra))
    assert_not dup.valid?
    assert_includes dup.errors[:user_id], "has already been taken"
  end

  test "sets enrolled_at on create" do
    e = Enrollment.create!(user: users(:other_student), course: courses(:algebra))
    assert_not_nil e.enrolled_at
  end

  test "completion_percentage with no lessons is 0" do
    course = Course.create!(title: "Empty", subject: subjects(:math), owner: users(:instructor))
    e = Enrollment.create!(user: users(:other_student), course: course)
    assert_equal 0, e.completion_percentage
  end

  test "completion_percentage counts completed progresses" do
    enrollment = enrollments(:student_in_algebra)
    Progress.find_or_initialize_by(enrollment: enrollment, lesson: lessons(:intro)).update!(status: :completed)
    total = courses(:algebra).lessons_required_for_completion.count
    assert_in_delta (1.0 / total * 100).round(1), enrollment.completion_percentage, 0.01
  end

  test "completion ignores draft lessons and their progresses" do
    enrollment = enrollments(:student_in_algebra)
    Progress.find_or_initialize_by(enrollment: enrollment, lesson: lessons(:intro)).update!(status: :completed)
    Progress.find_or_initialize_by(enrollment: enrollment, lesson: lessons(:draft_lesson)).update!(status: :completed)

    assert_equal 2, enrollment.lessons_required_count
    assert_equal 1, enrollment.lessons_completed_count
    assert_equal 50.0, enrollment.completion_percentage
  end

  test "published lessons can be fully completed while a draft remains incomplete" do
    enrollment = enrollments(:student_in_algebra)
    Progress.find_or_initialize_by(enrollment: enrollment, lesson: lessons(:intro)).update!(status: :completed)
    Progress.find_or_initialize_by(enrollment: enrollment, lesson: lessons(:advanced)).update!(status: :completed)

    assert enrollment.fully_completed?
    assert_includes Enrollment.completed, enrollment
  end

  test "a course with no published lessons is not fully completed" do
    course = Course.create!(title: "Draft only", subject: subjects(:math), owner: users(:instructor))
    course.lessons.create!(title: "Coming soon", position: 1)
    enrollment = Enrollment.create!(user: users(:other_student), course: course)

    assert_equal 0, enrollment.completion_percentage
    assert_not enrollment.fully_completed?
    assert_not_includes Enrollment.completed, enrollment
  end
end
