class AddLocaleToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :locale, :string, null: false, default: "en"
    add_column :users, :course_locales, :string, array: true, null: false, default: %w[en de]
    add_column :courses, :locale, :string, null: false, default: "en"
  end
end
