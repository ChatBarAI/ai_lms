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
    total = courses(:algebra).lessons.count
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
end
