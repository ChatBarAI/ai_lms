class CreateCoursePurchases < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :stripe_customer_id, :string
    # Price in cents (nil = free, 0 = free, > 0 = paid)
    add_column :courses, :price_cents, :integer, default: nil
    add_column :site_settings, :stripe_enabled, :boolean, default: true, null: false

    create_table :course_purchases do |t|
      t.references :user, null: false, foreign_key: true
      t.references :course, null: false, foreign_key: true
      t.integer :amount_cents, null: false
      t.string :stripe_session_id
      t.string :stripe_payment_intent_id

      t.timestamps
    end

    add_index :course_purchases, [ :user_id, :course_id ], unique: true
    add_index :course_purchases, :stripe_session_id, unique: true,
              where: "stripe_session_id IS NOT NULL"
  end
end
