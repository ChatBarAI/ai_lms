# Kinde sign-in links to an existing local account by email only when that
# account's email is verified (see User.from_kinde). Accounts linked to a
# provider have had their email verified by it. Every other account verifies
# by completing a password reset or setup link.
class AddEmailVerifiedAtToUsers < ActiveRecord::Migration[7.2]
  def up
    add_column :users, :email_verified_at, :datetime

    execute <<~SQL.squish
      UPDATE users SET email_verified_at = created_at
      WHERE provider IS NOT NULL AND provider <> ''
    SQL
  end

  def down
    remove_column :users, :email_verified_at
  end
end
