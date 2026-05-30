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

ActiveRecord::Schema[7.2].define(version: 2026_05_29_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "conversations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "name"
    t.boolean "read", default: false
    t.integer "conversation_type", default: 0
    t.index ["conversation_type"], name: "index_conversations_on_conversation_type"
  end

  create_table "jwt_denylists", force: :cascade do |t|
    t.string "jti"
    t.datetime "exp"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["jti"], name: "index_jwt_denylists_on_jti"
  end

  create_table "messages", force: :cascade do |t|
    t.bigint "conversation_id", null: false
    t.bigint "sender_id", null: false
    t.boolean "read", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "body"
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
    t.index ["sender_id"], name: "index_messages_on_sender_id"
  end

  create_table "onboardings", force: :cascade do |t|
    t.datetime "completed_at"
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_onboardings_on_user_id"
  end

  create_table "plans", force: :cascade do |t|
    t.string "name", null: false
    t.string "stripe_price_id"
    t.string "apple_product_id"
    t.string "google_product_id"
    t.decimal "amount", precision: 10, scale: 2
    t.string "currency", default: "usd"
    t.string "interval", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["apple_product_id"], name: "index_plans_on_apple_product_id", unique: true
    t.index ["google_product_id"], name: "index_plans_on_google_product_id", unique: true
    t.index ["stripe_price_id"], name: "index_plans_on_stripe_price_id", unique: true
  end

  create_table "subscription_events", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "subscription_id", null: false
    t.integer "event_type", null: false
    t.string "processor_event_id", null: false
    t.text "data"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["processor_event_id"], name: "index_subscription_events_on_processor_event_id", unique: true
    t.index ["subscription_id"], name: "index_subscription_events_on_subscription_id"
    t.index ["user_id"], name: "index_subscription_events_on_user_id"
  end

  create_table "subscriptions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.integer "processor", null: false
    t.decimal "amount", precision: 10, scale: 2
    t.string "currency", default: "usd"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "subscription_type", default: 0, null: false
    t.date "expiration_date"
    t.boolean "active", default: false
    t.integer "status", default: 0, null: false
    t.string "processor_id"
    t.index ["user_id"], name: "index_subscriptions_on_user_id"
    t.index ["user_id"], name: "index_subscriptions_on_user_id_active_unique", unique: true, where: "(subscription_type = 0)"
  end

  create_table "timer_runs", force: :cascade do |t|
    t.bigint "user_id"
    t.datetime "start_time", null: false
    t.datetime "end_time"
    t.integer "duration"
    t.boolean "submitted", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "active", default: false, null: false
    t.index ["user_id", "submitted"], name: "index_timer_runs_on_user_id_and_submitted"
    t.index ["user_id"], name: "index_timer_runs_on_user_id"
    t.index ["user_id"], name: "index_timer_runs_one_active_per_user", unique: true, where: "(active = true)"
  end

  create_table "user_conversations", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_id"], name: "index_user_conversations_on_conversation_id"
    t.index ["user_id", "conversation_id"], name: "index_user_conversations_on_user_id_and_conversation_id", unique: true
    t.index ["user_id"], name: "index_user_conversations_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "first_name"
    t.string "last_name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.string "stripe_customer_id"
    t.string "processor"
    t.string "jti"
    t.string "username"
    t.datetime "deleted_at"
    t.string "baby_name"
    t.integer "daily_nap_count", default: 3, null: false
    t.index ["deleted_at"], name: "index_users_on_deleted_at"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["jti"], name: "index_users_on_jti"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  add_foreign_key "messages", "conversations"
  add_foreign_key "messages", "users", column: "sender_id"
  add_foreign_key "onboardings", "users"
  add_foreign_key "subscription_events", "subscriptions"
  add_foreign_key "subscription_events", "users"
  add_foreign_key "subscriptions", "users"
  add_foreign_key "timer_runs", "users"
  add_foreign_key "user_conversations", "conversations"
  add_foreign_key "user_conversations", "users"
end
