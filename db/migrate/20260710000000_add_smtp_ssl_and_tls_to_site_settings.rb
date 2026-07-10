class AddSmtpSslAndTlsToSiteSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :site_settings, :smtp_ssl, :boolean
    add_column :site_settings, :smtp_tls, :boolean
  end
end
