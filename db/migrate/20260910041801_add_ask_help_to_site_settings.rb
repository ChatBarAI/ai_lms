class AddAskHelpToSiteSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :site_settings, :help_enabled, :boolean, default: false, null: false
    add_column :site_settings, :help_admin_token, :string
    add_column :site_settings, :help_instructor_token, :string
  end
end
