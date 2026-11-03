require "test_helper"

class EnrollmentTest < ActiveSupport::TestCase
  test "newly published lessons do not revoke an earned completion or prerequisites" do
    enrollment = enrollments(:student_in_algebra)
    progresses(:student_intro).update!(status: :completed)
    assert_nil enrollment.reload.completed_at
    enrollment.progresses.create!(lesson: lessons(:advanced), status: :completed)
    completed_at = enrollment.reload.completed_at
    assert_not_nil completed_at

    lessons(:draft_lesson).update!(published_at: Time.current)

    assert enrollment.reload.fully_completed?
    assert_equal 100.0, enrollment.completion_percentage
    assert_includes Enrollment.completed, enrollment
    CoursePrerequisite.create!(course: courses(:other_owner_course), prerequisite_course: courses(:algebra))
    assert Enrollment.new(user: users(:student), course: courses(:other_owner_course)).valid?

    travel 1.day do
      enrollment.progresses.create!(lesson: lessons(:draft_lesson), status: :completed)
    end
    assert_equal completed_at, enrollment.reload.completed_at
  end

  test "new lessons still count for learners who have not completed the course" do
    enrollment = enrollments(:student_in_algebra)
    progresses(:student_intro).update!(status: :completed)
    assert_equal 50.0, enrollment.reload.completion_percentage

    lessons(:draft_lesson).update!(published_at: Time.current)

    assert_nil enrollment.reload.completed_at
    assert_not enrollment.fully_completed?
    assert_equal 33.3, enrollment.completion_percentage
    assert_not_includes Enrollment.completed, enrollment
  end

  test "completion timestamp rolls back with the final lesson completion" do
    enrollment = enrollments(:student_in_algebra)
    progresses(:student_intro).update!(status: :completed)

    Progress.transaction do
      enrollment.progresses.create!(lesson: lessons(:advanced), status: :completed)
      assert_not_nil enrollment.reload.completed_at
      raise ActiveRecord::Rollback
    end

    assert_nil enrollment.reload.completed_at
    assert_not enrollment.fully_completed?
  end

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

  test "blocks create when prerequisites unmet" do
    CoursePrerequisite.create!(course: courses(:other_owner_course), prerequisite_course: courses(:algebra))
    enrollment = Enrollment.new(user: users(:other_student), course: courses(:other_owner_course))
    assert_not enrollment.valid?
    assert enrollment.errors[:base].any? { |m| m.include?("Complete these courses first") }
  end

  test "allows create when skip_prerequisite_check" do
    CoursePrerequisite.create!(course: courses(:other_owner_course), prerequisite_course: courses(:algebra))
    enrollment = Enrollment.new(user: users(:other_student), course: courses(:other_owner_course), skip_prerequisite_check: true)
    assert enrollment.valid?
  end

  test "allows create when prerequisites fully completed" do
    CoursePrerequisite.create!(course: courses(:other_owner_course), prerequisite_course: courses(:algebra))
    enrollment = enrollments(:student_in_algebra)
    courses(:algebra).lessons.find_each do |lesson|
      Progress.find_or_initialize_by(enrollment: enrollment, lesson: lesson).update!(status: :completed)
    end

    assert Enrollment.new(user: users(:student), course: courses(:other_owner_course)).valid?
  end

  test "completion ignores draft lessons and their progresses" do
    enrollment = enrollments(:student_in_algebra)
    Progress.find_or_initialize_by(enrollment: enrollment, lesson: lessons(:intro)).update!(status: :completed)
    Progress.find_or_initialize_by(enrollment: enrollment, lesson: lessons(:draft_lesson)).update!(status: :completed)

    assert_equal 2, enrollment.lessons_required_count
    assert_equal 1, enrollment.lessons_completed_count
    assert_equal 50.0, enrollment.completion_percentage
  end

  test "completion percentage includes partial lesson progress without awarding completion" do
    enrollment = enrollments(:student_in_algebra)
    progresses(:student_intro).update!(score: 40)

    assert_equal 20, enrollment.completion_percentage
    assert_equal 0, enrollment.lessons_completed_count
    assert_not enrollment.fully_completed?
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
