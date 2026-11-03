class AddCompletedAtToEnrollments < ActiveRecord::Migration[7.2]
  def change
    add_column :enrollments, :completed_at, :datetime
  end
end
