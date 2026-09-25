class CreateCoursePrerequisites < ActiveRecord::Migration[7.2]
  def change
    create_table :course_prerequisites do |t|
      t.references :course, null: false, foreign_key: true
      t.references :prerequisite_course, null: false, foreign_key: { to_table: :courses }
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_index :course_prerequisites, [ :course_id, :prerequisite_course_id ], unique: true, name: "index_course_prerequisites_uniqueness"
    add_check_constraint :course_prerequisites, "course_id <> prerequisite_course_id", name: "course_prerequisites_not_self"
  end
end
