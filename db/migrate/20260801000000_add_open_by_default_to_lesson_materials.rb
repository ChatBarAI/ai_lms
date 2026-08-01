class AddOpenByDefaultToLessonMaterials < ActiveRecord::Migration[7.2]
  def change
    add_column :lesson_materials, :open_by_default, :boolean, default: false, null: false
  end
end
