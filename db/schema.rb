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

ActiveRecord::Schema[8.1].define(version: 2026_08_17_034005) do
  create_table "api_tokens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.datetime "last_used_at"
    t.string "plugin_name", null: false
    t.integer "publisher_id", null: false
    t.datetime "revoked_at"
    t.string "token_digest", null: false
    t.string "token_hint", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["publisher_id"], name: "index_api_tokens_on_publisher_id"
    t.index ["token_digest"], name: "index_api_tokens_on_token_digest", unique: true
    t.index ["user_id"], name: "index_api_tokens_on_user_id"
  end

  create_table "audit_events", force: :cascade do |t|
    t.string "action", null: false
    t.datetime "created_at", null: false
    t.json "metadata", default: {}, null: false
    t.boolean "public", default: false, null: false
    t.integer "subject_id", null: false
    t.string "subject_type", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["public", "created_at"], name: "index_audit_events_on_public_and_created_at"
    t.index ["subject_type", "subject_id"], name: "index_audit_events_on_subject"
    t.index ["user_id"], name: "index_audit_events_on_user_id"
  end

  create_table "daily_downloads", force: :cascade do |t|
    t.integer "count", default: 0, null: false
    t.date "date", null: false
    t.integer "plugin_version_id", null: false
    t.index ["plugin_version_id", "date"], name: "index_daily_downloads_on_plugin_version_id_and_date", unique: true
    t.index ["plugin_version_id"], name: "index_daily_downloads_on_plugin_version_id"
  end

  create_table "memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "publisher_id", null: false
    t.integer "role", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["publisher_id", "user_id"], name: "index_memberships_on_publisher_id_and_user_id", unique: true
    t.index ["publisher_id"], name: "index_memberships_on_publisher_id"
    t.index ["user_id"], name: "index_memberships_on_user_id"
  end

  create_table "plugin_versions", force: :cascade do |t|
    t.json "capability_fingerprint"
    t.datetime "created_at", null: false
    t.integer "downloads_count", default: 0, null: false
    t.string "license"
    t.json "manifest", null: false
    t.string "min_omarchy_version"
    t.integer "plugin_id", null: false
    t.datetime "published_at"
    t.text "review_notes"
    t.string "sha256", null: false
    t.integer "size_bytes", null: false
    t.integer "state", default: 0, null: false
    t.datetime "updated_at", null: false
    t.string "version", null: false
    t.string "version_sort_key", null: false
    t.string "yank_reason"
    t.datetime "yanked_at"
    t.index ["plugin_id", "version"], name: "index_plugin_versions_on_plugin_id_and_version", unique: true
    t.index ["plugin_id"], name: "index_plugin_versions_on_plugin_id"
  end

  create_table "plugins", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "downloads_count", default: 0, null: false
    t.string "homepage_url"
    t.json "kinds", default: [], null: false
    t.string "latest_version"
    t.string "name", null: false
    t.string "normalized_name", null: false
    t.integer "publisher_id", null: false
    t.text "readme"
    t.string "repository_url"
    t.integer "state", default: 0, null: false
    t.string "summary"
    t.datetime "updated_at", null: false
    t.index ["normalized_name"], name: "index_plugins_on_normalized_name"
    t.index ["publisher_id", "name"], name: "index_plugins_on_publisher_id_and_name", unique: true
    t.index ["publisher_id"], name: "index_plugins_on_publisher_id"
  end

  create_table "publishers", force: :cascade do |t|
    t.text "bio"
    t.boolean "claimed", default: true, null: false
    t.datetime "created_at", null: false
    t.string "display_name"
    t.integer "kind", default: 0, null: false
    t.string "name", null: false
    t.string "normalized_name", null: false
    t.string "seed_source_url"
    t.datetime "suspended_at"
    t.datetime "updated_at", null: false
    t.boolean "verified", default: false, null: false
    t.string "website"
    t.index ["name"], name: "index_publishers_on_name", unique: true
    t.index ["normalized_name"], name: "index_publishers_on_normalized_name", unique: true
  end

  create_table "revocations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "created_by_id", null: false
    t.integer "plugin_id", null: false
    t.string "reason", null: false
    t.datetime "updated_at", null: false
    t.string "version"
    t.index ["created_by_id"], name: "index_revocations_on_created_by_id"
    t.index ["plugin_id", "version"], name: "index_revocations_on_plugin_id_and_version", unique: true
    t.index ["plugin_id"], name: "index_revocations_on_plugin_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin", default: false, null: false
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "name"
    t.json "otp_backup_codes"
    t.datetime "otp_enabled_at"
    t.string "otp_secret"
    t.string "password_digest", null: false
    t.datetime "sensitive_change_at"
    t.datetime "suspended_at"
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "api_tokens", "publishers"
  add_foreign_key "api_tokens", "users"
  add_foreign_key "audit_events", "users"
  add_foreign_key "daily_downloads", "plugin_versions"
  add_foreign_key "memberships", "publishers"
  add_foreign_key "memberships", "users"
  add_foreign_key "plugin_versions", "plugins"
  add_foreign_key "plugins", "publishers"
  add_foreign_key "revocations", "plugins"
  add_foreign_key "revocations", "users", column: "created_by_id"
  add_foreign_key "sessions", "users"
end
