class AddPublicAccessEnabledToCourses < ActiveRecord::Migration[7.2]
  def change
    add_column :courses, :public_access_enabled, :boolean, null: false, default: false
  end
end
