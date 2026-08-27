class AddChatbarFieldsToLessonMaterials < ActiveRecord::Migration[7.2]
  def change
    add_column :lesson_materials, :chatbar_token, :string
    add_column :lesson_materials, :chatbar_prompt, :text
  end
end
