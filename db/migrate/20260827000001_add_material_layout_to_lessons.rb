class AddMaterialLayoutToLessons < ActiveRecord::Migration[7.2]
  def change
    add_column :lessons, :material_layout, :string, default: "stacked", null: false
  end
end
