class CreateAiMaterialDesigner < ActiveRecord::Migration[7.2]
  def change
    create_table :ai_model_configurations do |t|
      t.string :name, null: false
      t.text :description
      t.string :provider, null: false, default: "openai"
      t.string :model, null: false, default: "gpt-5.6-sol"
      t.text :api_key
      t.string :base_url, null: false, default: "https://api.openai.com/v1"
      t.text :system_prompt
      t.boolean :enabled, null: false, default: true
      t.integer :context_window_tokens, null: false, default: 128_000
      t.decimal :input_cost_cents_per_million_tokens, precision: 12, scale: 6, null: false, default: 0
      t.decimal :output_cost_cents_per_million_tokens, precision: 12, scale: 6, null: false, default: 0
      t.references :created_by, foreign_key: { to_table: :users }
      t.timestamps
    end

    create_table :material_design_revisions do |t|
      t.references :lesson_material, null: false, foreign_key: true
      t.references :ai_model_configuration, null: false, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.references :parent_revision, foreign_key: { to_table: :material_design_revisions }
      t.string :status, null: false, default: "queued"
      t.text :request, null: false
      t.text :source_html
      t.text :generated_html
      t.text :sanitized_html
      t.text :error_message
      t.string :provider_request_id
      t.integer :input_tokens
      t.integer :output_tokens
      t.datetime :accepted_at
      t.timestamps
    end

    add_index :material_design_revisions, [ :lesson_material_id, :created_at ]
    add_index :material_design_revisions, :lesson_material_id,
              unique: true,
              where: "status IN ('queued', 'generating')",
              name: "index_one_active_design_revision_per_material"

    create_table :material_design_assets do |t|
      t.references :lesson_material, null: false, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.string :name, null: false
      t.text :description
      t.string :alt_text
      t.string :role, null: false, default: "content"
      t.timestamps
    end

    add_index :material_design_assets, :role

    add_reference :lesson_materials, :source_material,
                  foreign_key: { to_table: :lesson_materials, on_delete: :nullify }
    add_reference :lesson_materials, :copied_by,
                  foreign_key: { to_table: :users, on_delete: :nullify }
  end
end
