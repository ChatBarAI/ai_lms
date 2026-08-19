class CoursePrerequisite < ApplicationRecord
  belongs_to :course
  belongs_to :prerequisite_course, class_name: "Course"

  validates :prerequisite_course_id, uniqueness: { scope: :course_id }
  validate :not_self
  validate :no_cycle

  private

  def not_self
    return if course_id.blank? || prerequisite_course_id.blank?
    return unless course_id == prerequisite_course_id

    errors.add(:prerequisite_course_id, "can't be the same as the course")
  end

  # Adding B→requires→A is a cycle if A already requires B (transitively).
  def no_cycle
    return if course_id.blank? || prerequisite_course_id.blank?
    return if course_id == prerequisite_course_id

    seen = {}
    queue = [ prerequisite_course_id ]
    while (id = queue.shift)
      next if seen[id]

      seen[id] = true
      if id == course_id
        errors.add(:prerequisite_course_id, "would create a circular dependency")
        return
      end
      CoursePrerequisite.where(course_id: id).pluck(:prerequisite_course_id).each { |pid| queue << pid }
    end
  end
end
