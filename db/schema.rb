# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 2026_06_30_000001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "action_text_rich_texts", force: :cascade do |t|
    t.string "name", null: false
    t.text "body"
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id", "name"], name: "index_action_text_rich_texts_uniqueness", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "certificates", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "course_id", null: false
    t.datetime "issued_at", null: false
    t.string "token", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["course_id"], name: "index_certificates_on_course_id"
    t.index ["token"], name: "index_certificates_on_token", unique: true
    t.index ["user_id", "course_id"], name: "index_certificates_on_user_id_and_course_id", unique: true
    t.index ["user_id"], name: "index_certificates_on_user_id"
  end

  create_table "courses", force: :cascade do |t|
    t.bigint "subject_id"
    t.bigint "owner_id", null: false
    t.string "title"
    t.string "slug"
    t.text "description"
    t.datetime "published_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "certificate_layout", default: {}, null: false
    t.string "locale", default: "en", null: false
    t.boolean "public_access_enabled", default: false, null: false
    t.index ["owner_id"], name: "index_courses_on_owner_id"
    t.index ["slug"], name: "index_courses_on_slug", unique: true
    t.index ["subject_id"], name: "index_courses_on_subject_id"
  end

  create_table "enrollments", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "course_id", null: false
    t.integer "role"
    t.datetime "enrolled_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["course_id"], name: "index_enrollments_on_course_id"
    t.index ["user_id", "course_id"], name: "index_enrollments_on_user_id_and_course_id", unique: true
    t.index ["user_id"], name: "index_enrollments_on_user_id"
  end

  create_table "lesson_material_acknowledgements", force: :cascade do |t|
    t.bigint "lesson_material_id", null: false
    t.bigint "enrollment_id", null: false
    t.datetime "acknowledged_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["enrollment_id"], name: "index_lesson_material_acknowledgements_on_enrollment_id"
    t.index ["lesson_material_id", "enrollment_id"], name: "index_lesson_material_acks_on_material_and_enrollment", unique: true
    t.index ["lesson_material_id"], name: "index_lesson_material_acknowledgements_on_lesson_material_id"
  end

  create_table "lesson_materials", force: :cascade do |t|
    t.bigint "lesson_id", null: false
    t.string "title", null: false
    t.integer "kind", default: 0, null: false
    t.integer "position", default: 0, null: false
    t.boolean "required", default: true, null: false
    t.text "raw_html_content"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "url"
    t.index ["lesson_id", "position"], name: "index_lesson_materials_on_lesson_id_and_position"
    t.index ["lesson_id"], name: "index_lesson_materials_on_lesson_id"
  end

  create_table "lessons", force: :cascade do |t|
    t.bigint "course_id", null: false
    t.string "title"
    t.integer "position"
    t.string "cbai_token"
    t.datetime "published_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "video_url"
    t.string "cbai_api_key"
    t.string "cbai_display_mode"
    t.integer "cbai_id"
    t.integer "pass_mark"
    t.integer "duration_minutes"
    t.string "quiz_layout", default: "scrolling", null: false
    t.boolean "retry_incorrect_only", default: false, null: false
    t.integer "free_text_pass_level", default: 6, null: false
    t.string "synthesia_api_key"
    t.string "ai_tutor_provider"
    t.string "anam_api_key"
    t.string "anam_persona_id"
    t.string "heygen_api_key"
    t.boolean "ratings_enabled", default: true, null: false
    t.string "custom_tutor_embed_url"
    t.string "custom_tutor_embed_type"
    t.text "custom_tutor_embed_script"
    t.index ["cbai_token"], name: "index_lessons_on_cbai_token"
    t.index ["course_id", "position"], name: "index_lessons_on_course_id_and_position"
    t.index ["course_id"], name: "index_lessons_on_course_id"
  end

  create_table "organizations", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.string "contact_email"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "kinde_connection_id"
    t.string "kinde_connection_provider", default: "microsoft"
    t.boolean "sso_auto_enroll", default: true, null: false
    t.boolean "sso_required", default: false, null: false
    t.string "sso_domain"
    t.index ["kinde_connection_id"], name: "index_organizations_on_kinde_connection_id", unique: true, where: "(kinde_connection_id IS NOT NULL)"
    t.index ["name"], name: "index_organizations_on_name"
    t.index ["slug"], name: "index_organizations_on_slug", unique: true
    t.index ["sso_domain"], name: "index_organizations_on_sso_domain", unique: true, where: "(sso_domain IS NOT NULL)"
  end

  create_table "progresses", force: :cascade do |t|
    t.bigint "enrollment_id", null: false
    t.bigint "lesson_id", null: false
    t.integer "status"
    t.datetime "completed_at"
    t.decimal "score"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "scoring_submitted_at"
    t.integer "scoring_retry_count", default: 0, null: false
    t.index ["enrollment_id", "lesson_id"], name: "index_progresses_on_enrollment_id_and_lesson_id", unique: true
    t.index ["enrollment_id"], name: "index_progresses_on_enrollment_id"
    t.index ["lesson_id"], name: "index_progresses_on_lesson_id"
  end

  create_table "question_answers", force: :cascade do |t|
    t.bigint "enrollment_id", null: false
    t.bigint "question_id", null: false
    t.text "answer_text"
    t.integer "ai_score"
    t.datetime "scored_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["enrollment_id", "question_id"], name: "index_question_answers_on_enrollment_id_and_question_id", unique: true
    t.index ["enrollment_id"], name: "index_question_answers_on_enrollment_id"
    t.index ["question_id"], name: "index_question_answers_on_question_id"
  end

  create_table "question_generation_tasks", force: :cascade do |t|
    t.bigint "lesson_id", null: false
    t.string "cbai_task_id"
    t.string "status", default: "pending", null: false
    t.text "prompt"
    t.jsonb "task_payload"
    t.jsonb "response_payload"
    t.text "error_message"
    t.string "callback_secret", null: false
    t.integer "questions_created_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["callback_secret"], name: "index_question_generation_tasks_on_callback_secret", unique: true
    t.index ["cbai_task_id"], name: "index_question_generation_tasks_on_cbai_task_id"
    t.index ["lesson_id"], name: "index_question_generation_tasks_on_lesson_id"
  end

  create_table "questions", force: :cascade do |t|
    t.bigint "lesson_id", null: false
    t.text "prompt"
    t.integer "kind"
    t.text "choices"
    t.text "correct_answer"
    t.integer "points"
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["lesson_id"], name: "index_questions_on_lesson_id"
  end

  create_table "quiz_attempts", force: :cascade do |t|
    t.bigint "progress_id", null: false
    t.bigint "enrollment_id", null: false
    t.bigint "lesson_id", null: false
    t.integer "attempt_number", null: false
    t.integer "status", default: 0, null: false
    t.decimal "score", precision: 5, scale: 2
    t.datetime "submitted_at", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["enrollment_id", "lesson_id", "created_at"], name: "index_quiz_attempts_on_enrollment_lesson_created"
    t.index ["enrollment_id"], name: "index_quiz_attempts_on_enrollment_id"
    t.index ["lesson_id"], name: "index_quiz_attempts_on_lesson_id"
    t.index ["progress_id", "attempt_number"], name: "index_quiz_attempts_on_progress_id_and_attempt_number", unique: true
    t.index ["progress_id"], name: "index_quiz_attempts_on_progress_id"
  end

  create_table "ratings", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "lesson_id", null: false
    t.integer "stars"
    t.text "comment"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["lesson_id"], name: "index_ratings_on_lesson_id"
    t.index ["user_id", "lesson_id"], name: "index_ratings_on_user_id_and_lesson_id", unique: true
    t.index ["user_id"], name: "index_ratings_on_user_id"
  end

  create_table "site_settings", force: :cascade do |t|
    t.string "brand_name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "pass_mark", default: 70, null: false
    t.string "app_url"
    t.string "theme_mode", default: "system", null: false
    t.string "page_bg_light", default: "#f9fafb"
    t.string "page_fg_light", default: "#111827"
    t.string "nav_bg_light", default: "#ffffff"
    t.string "nav_fg_light", default: "#374151"
    t.string "admin_nav_bg_light", default: "#111827"
    t.string "admin_nav_fg_light", default: "#ffffff"
    t.string "page_bg_dark", default: "#111827"
    t.string "page_fg_dark", default: "#f3f4f6"
    t.string "nav_bg_dark", default: "#1f2937"
    t.string "nav_fg_dark", default: "#d1d5db"
    t.string "admin_nav_bg_dark", default: "#030712"
    t.string "admin_nav_fg_dark", default: "#ffffff"
    t.string "btn_primary_bg_light", default: "#4f46e5"
    t.string "btn_primary_fg_light", default: "#ffffff"
    t.string "btn_primary_bg_dark", default: "#6366f1"
    t.string "btn_primary_fg_dark", default: "#ffffff"
    t.string "btn_success_bg_light", default: "#16a34a"
    t.string "btn_success_fg_light", default: "#ffffff"
    t.string "btn_success_bg_dark", default: "#22c55e"
    t.string "btn_success_fg_dark", default: "#ffffff"
    t.string "btn_danger_bg_light", default: "#dc2626"
    t.string "btn_danger_fg_light", default: "#ffffff"
    t.string "btn_danger_bg_dark", default: "#ef4444"
    t.string "btn_danger_fg_dark", default: "#ffffff"
    t.boolean "show_brand_name", default: true, null: false
    t.jsonb "terminology", default: {}, null: false
    t.text "hero_content"
    t.string "hero_content_format", default: "markdown", null: false
    t.boolean "subjects_enabled", default: true, null: false
    t.string "certificate_heading", default: "Certificate of Completion"
    t.string "certificate_body", default: "This certifies that"
    t.string "certificate_signatory_name"
    t.string "certificate_signatory_title"
    t.boolean "invert_logo_on_dark", default: false, null: false
    t.string "card_bg_light", default: "#ffffff"
    t.string "card_bg_dark", default: "#1f2937"
    t.string "redis_url"
    t.boolean "allow_guest_access", default: true, null: false
    t.boolean "self_service_sign_up_enabled", default: false, null: false
    t.boolean "kinde_google_jit_provisioning_enabled", default: false, null: false
    t.boolean "kinde_microsoft_jit_provisioning_enabled", default: true, null: false
    t.boolean "kinde_google_sign_in_enabled", default: true, null: false
    t.boolean "kinde_microsoft_sign_in_enabled", default: true, null: false
    t.string "brand_primary_color", default: "#2563eb"
  end

  create_table "subjects", force: :cascade do |t|
    t.string "name"
    t.string "slug"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_subjects_on_slug", unique: true
  end

  create_table "taggings", force: :cascade do |t|
    t.bigint "tag_id", null: false
    t.string "taggable_type", null: false
    t.bigint "taggable_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["tag_id", "taggable_type", "taggable_id"], name: "index_taggings_uniqueness", unique: true
    t.index ["tag_id"], name: "index_taggings_on_tag_id"
    t.index ["taggable_type", "taggable_id"], name: "index_taggings_on_taggable"
  end

  create_table "tags", force: :cascade do |t|
    t.string "name", null: false
    t.string "color", default: "#6366f1", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_tags_on_name", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.integer "failed_attempts", default: 0, null: false
    t.string "unlock_token"
    t.datetime "locked_at"
    t.string "provider"
    t.string "uid"
    t.string "name"
    t.string "image_url"
    t.integer "role", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "organization_id"
    t.string "locale", default: "en", null: false
    t.string "course_locales", default: ["en", "de"], null: false, array: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["organization_id"], name: "index_users_on_organization_id"
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["unlock_token"], name: "index_users_on_unlock_token", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "certificates", "courses"
  add_foreign_key "certificates", "users"
  add_foreign_key "courses", "subjects"
  add_foreign_key "courses", "users", column: "owner_id"
  add_foreign_key "enrollments", "courses"
  add_foreign_key "enrollments", "users"
  add_foreign_key "lesson_material_acknowledgements", "enrollments"
  add_foreign_key "lesson_material_acknowledgements", "lesson_materials"
  add_foreign_key "lesson_materials", "lessons"
  add_foreign_key "lessons", "courses"
  add_foreign_key "progresses", "enrollments"
  add_foreign_key "progresses", "lessons"
  add_foreign_key "question_answers", "enrollments"
  add_foreign_key "question_answers", "questions"
  add_foreign_key "question_generation_tasks", "lessons"
  add_foreign_key "questions", "lessons"
  add_foreign_key "quiz_attempts", "enrollments"
  add_foreign_key "quiz_attempts", "lessons"
  add_foreign_key "quiz_attempts", "progresses"
  add_foreign_key "ratings", "lessons"
  add_foreign_key "ratings", "users"
  add_foreign_key "taggings", "tags"
  add_foreign_key "users", "organizations"
end
