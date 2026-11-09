class AddRevokedAtToCertificates < ActiveRecord::Migration[7.2]
  def change
    add_column :certificates, :revoked_at, :datetime
  end
end
