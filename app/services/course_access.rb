# Catalogue readability is intentionally separate from learning access.
class CourseAccess
  def self.conditions(user)
    [
      { access_policy: "free" }, { owner_id: user.id },
      { id: CourseEntitlement.effective.where(user_id: user.id).distinct.pluck(:course_id) }
    ]
  end

  def self.allowed?(user, course)
    course.access_policy == "free" || user&.admin? || course.owner_id == user&.id ||
      (user && CourseEntitlement.effective.exists?(user_id: user.id, course_id: course.id))
  end
end
