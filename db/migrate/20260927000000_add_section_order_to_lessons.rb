class AddSectionOrderToLessons < ActiveRecord::Migration[7.2]
  def change
    add_column :lessons, :section_order, :jsonb, default: [], null: false
  end
end
