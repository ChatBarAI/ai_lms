class AddChatbarLayoutToLessonMaterials < ActiveRecord::Migration[7.2]
  def change
    add_column :lesson_materials, :chatbar_layout, :string, default: "stacked", null: false
  end
end
