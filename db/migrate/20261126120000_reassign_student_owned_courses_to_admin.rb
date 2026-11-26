# Courses may only be owned by instructors or admins (Course#owner_can_author_courses).
# Earlier releases allowed any user as owner, so a course owned by a student would
# fail validation the next time anyone saved it. Hand such courses to the first
# admin (lowest id), who can reassign them in Admin -> Courses.
#
# Plain SQL so later model changes cannot break this migration. Role values match
# User's enum: student 0, admin 2.
class ReassignStudentOwnedCoursesToAdmin < ActiveRecord::Migration[7.2]
  STUDENT_ROLE = 0
  ADMIN_ROLE = 2

  def up
    courses = select_rows(<<~SQL.squish)
      SELECT courses.id, courses.owner_id
      FROM courses
      INNER JOIN users ON users.id = courses.owner_id
      WHERE users.role = #{STUDENT_ROLE}
      ORDER BY courses.id
    SQL
    return if courses.empty?

    admin_id = select_value("SELECT id FROM users WHERE role = #{ADMIN_ROLE} ORDER BY id LIMIT 1")
    if admin_id.nil?
      say "WARNING: #{courses.size} course(s) are owned by students but there is no admin to reassign them to. " \
          "Course ids: #{courses.map(&:first).join(', ')}. Change their owner by hand."
      return
    end

    courses.each do |course_id, owner_id|
      say "Course #{course_id}: owner user #{owner_id} (student) -> admin user #{admin_id}"
    end

    execute(<<~SQL.squish)
      UPDATE courses
      SET owner_id = #{Integer(admin_id)}, updated_at = CURRENT_TIMESTAMP
      WHERE id IN (#{courses.map { |id, _| Integer(id) }.join(', ')})
    SQL
  end

  def down
    # Nothing to undo: the previous owners are no longer valid course owners.
  end
end
