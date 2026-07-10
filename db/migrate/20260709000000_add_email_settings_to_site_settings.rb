class AddEmailSettingsToSiteSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :site_settings, :mail_delivery_method, :string
    add_column :site_settings, :mailer_sender, :string
    add_column :site_settings, :smtp_address, :string
    add_column :site_settings, :smtp_port, :integer
    add_column :site_settings, :smtp_domain, :string
    add_column :site_settings, :smtp_username, :string
    add_column :site_settings, :smtp_password, :string
    add_column :site_settings, :smtp_authentication, :string
    add_column :site_settings, :smtp_enable_starttls_auto, :boolean
    add_column :site_settings, :smtp_openssl_verify_mode, :string
    add_column :site_settings, :sendmail_location, :string
    add_column :site_settings, :sendmail_arguments, :string
  end
end
