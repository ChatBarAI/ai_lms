require "test_helper"

class CoursePrerequisiteTest < ActiveSupport::TestCase
  test "rejects self reference" do
    edge = CoursePrerequisite.new(course: courses(:algebra), prerequisite_course: courses(:algebra))
    assert_not edge.valid?
    assert_includes edge.errors[:prerequisite_course_id], "can't be the same as the course"
  end

  test "rejects cycles" do
    CoursePrerequisite.create!(course: courses(:other_owner_course), prerequisite_course: courses(:algebra))
    edge = CoursePrerequisite.new(course: courses(:algebra), prerequisite_course: courses(:other_owner_course))
    assert_not edge.valid?
    assert_includes edge.errors[:prerequisite_course_id], "would create a circular dependency"
  end

  test "missing_prerequisites_for lists unmet courses" do
    CoursePrerequisite.create!(course: courses(:other_owner_course), prerequisite_course: courses(:algebra))
    missing = courses(:other_owner_course).missing_prerequisites_for(users(:other_student))
    assert_equal [ courses(:algebra) ], missing
  end

  test "prerequisites_met_by? when fully completed" do
    CoursePrerequisite.create!(course: courses(:other_owner_course), prerequisite_course: courses(:algebra))
    enrollment = enrollments(:student_in_algebra)
    courses(:algebra).lessons.find_each do |lesson|
      Progress.find_or_initialize_by(enrollment: enrollment, lesson: lesson).update!(status: :completed)
    end

    assert courses(:other_owner_course).prerequisites_met_by?(users(:student))
  end
end
