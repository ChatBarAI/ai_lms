require "test_helper"
require Rails.root.join("db/migrate/20261126120000_reassign_student_owned_courses_to_admin")

class ReassignStudentOwnedCoursesToAdminTest < ActiveSupport::TestCase
  def migrate_up
    migration = ReassignStudentOwnedCoursesToAdmin.new
    migration.verbose = false
    migration.migrate(:up)
  end

  test "reassigns student-owned courses to the first admin and leaves others alone" do
    student_course = courses(:algebra)
    student_course.update_columns(owner_id: users(:student).id)
    first_admin = User.admin.order(:id).first

    migrate_up

    assert_equal first_admin.id, student_course.reload.owner_id
    assert student_course.valid?, student_course.errors.full_messages.to_sentence
    assert_equal users(:instructor).id, courses(:draft_course).reload.owner_id
    assert_equal users(:other_instructor).id, courses(:other_owner_course).reload.owner_id
  end

  test "leaves student-owned courses unchanged when there is no admin" do
    student_course = courses(:algebra)
    student_course.update_columns(owner_id: users(:student).id)
    User.admin.update_all(role: User.roles[:instructor])

    migrate_up

    assert_equal users(:student).id, student_course.reload.owner_id
  end

  test "does nothing when no course is owned by a student" do
    owners_before = Course.order(:id).pluck(:id, :owner_id)

    migrate_up

    assert_equal owners_before, Course.order(:id).pluck(:id, :owner_id)
  end
end
