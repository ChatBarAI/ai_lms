class AddLearningOrderToCourses < ActiveRecord::Migration[7.2]
  def change
    add_column :courses, :learning_order, :integer
    add_index :courses, :learning_order
  end
end
