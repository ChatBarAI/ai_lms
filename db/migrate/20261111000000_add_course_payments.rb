class AddCoursePayments < ActiveRecord::Migration[7.2]
  def change
    add_column :courses, :access_policy, :string, default: "free", null: false
    add_column :courses, :price_minor, :integer
    add_column :courses, :price_currency, :string
    add_check_constraint :courses, "access_policy IN ('free', 'entitlement_required')", name: "course_access_policy"
    add_check_constraint :courses, "access_policy = 'free' OR (price_minor > 0 AND price_currency IS NOT NULL)", name: "paid_course_price"
    add_column :enrollments, :archived_at, :datetime
    add_column :site_settings, :payments_enabled, :boolean, default: false, null: false
    add_column :site_settings, :payment_currency, :string, default: "eur", null: false
    add_column :site_settings, :payment_tax_mode, :string, default: "unconfigured", null: false
    add_column :site_settings, :payment_tax_behavior, :string, default: "exclusive", null: false
    add_column :site_settings, :payment_terms_url, :string
    add_column :site_settings, :payment_support_email, :string
    add_column :site_settings, :payment_seller_name, :string
    add_column :site_settings, :payment_live_ready, :boolean, default: false, null: false
    add_column :site_settings, :payment_recovery_at, :datetime
    add_column :site_settings, :stripe_secret_key, :text
    add_column :site_settings, :stripe_webhook_secret, :text
    add_column :site_settings, :stripe_account_id, :text

    create_table :purchases do |t|
      t.references :user, null: false, foreign_key: true
      t.references :course, null: false, foreign_key: true
      t.string :provider, default: "stripe", null: false
      t.string :account_id, null: false
      t.boolean :livemode, null: false
      t.string :course_title, null: false
      t.integer :amount_minor, null: false
      t.string :currency, null: false
      t.string :tax_mode, null: false
      t.string :tax_behavior, null: false
      t.string :return_base_url, null: false
      t.string :attempt_key, null: false
      t.jsonb :eligibility, default: {}, null: false
      t.string :checkout_session_id
      t.string :checkout_url
      t.datetime :checkout_expires_at
      t.string :payment_intent_id
      t.string :payment_state, default: "pending", null: false
      t.string :fulfilment_state, default: "pending", null: false
      t.integer :base_minor
      t.integer :tax_minor
      t.integer :total_minor
      t.integer :refunded_minor, default: 0, null: false
      t.string :exception_reason
      t.datetime :fulfilled_at
      t.datetime :reconciled_at
      t.timestamps
    end
    add_index :purchases, :attempt_key, unique: true
    add_index :purchases, [ :account_id, :livemode, :checkout_session_id ], unique: true, name: "purchase_session_identity"
    add_index :purchases, [ :account_id, :livemode, :payment_intent_id ], unique: true, name: "purchase_payment_identity"
    add_index :purchases, [ :user_id, :course_id ], unique: true, where: "payment_state = 'pending'", name: "one_pending_course_purchase"
    add_check_constraint :purchases, "amount_minor > 0 AND refunded_minor >= 0", name: "purchase_amounts"

    create_table :course_entitlements do |t|
      t.references :user, null: false, foreign_key: true
      t.references :course, null: false, foreign_key: true
      t.references :purchase, foreign_key: true, index: { unique: true }
      t.references :granted_by, foreign_key: { to_table: :users }
      t.string :source, null: false
      t.string :source_reference, null: false
      t.string :status, default: "active", null: false
      t.datetime :starts_at, null: false
      t.datetime :expires_at
      t.string :reason, null: false
      t.datetime :revoked_at
      t.datetime :suspended_at
      t.timestamps
    end
    add_index :course_entitlements, [ :source, :source_reference ], unique: true
    add_index :course_entitlements, [ :user_id, :course_id, :status ], name: "effective_course_grants"
    add_check_constraint :course_entitlements, "expires_at IS NULL OR expires_at > starts_at", name: "entitlement_time_window"
    add_check_constraint :course_entitlements, "status IN ('active', 'suspended', 'revoked')", name: "entitlement_status"

    create_table :entitlement_events do |t|
      t.references :course_entitlement, null: false, foreign_key: true
      t.references :actor, foreign_key: { to_table: :users }
      t.string :source, null: false
      t.string :action, null: false
      t.string :reason, null: false
      t.string :correlation_reference, null: false
      t.datetime :created_at, null: false
    end
    create_table :payment_events do |t|
      t.string :provider_event_id, null: false
      t.string :account_id, null: false
      t.boolean :livemode, null: false
      t.string :event_type, null: false
      t.string :object_id, null: false
      t.string :state, default: "pending", null: false
      t.integer :attempts, default: 0, null: false
      t.string :error_summary
      t.datetime :processed_at
      t.timestamps
    end
    add_index :payment_events, [ :account_id, :livemode, :provider_event_id ], unique: true, name: "payment_event_identity"
    add_index :payment_events, [ :state, :updated_at ]
  end
end
