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
end
