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

ActiveRecord::Schema[8.1].define(version: 2026_04_15_174156) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "citext"
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"
  enable_extension "unaccent"

  create_table "action_text_rich_texts", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id", "name"], name: "index_action_text_rich_texts_uniqueness", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", precision: nil, null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "announcement_dismisses", force: :cascade do |t|
    t.bigint "announcement_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["announcement_id"], name: "index_announcement_dismisses_on_announcement_id"
    t.index ["user_id"], name: "index_announcement_dismisses_on_user_id"
  end

  create_table "announcements", id: :serial, force: :cascade do |t|
    t.boolean "active", default: true
    t.datetime "created_at", precision: nil, null: false
    t.text "description"
    t.date "end_date"
    t.string "public_goal"
    t.datetime "updated_at", precision: nil, null: false
    t.integer "user_id"
  end

  create_table "answers", id: :serial, force: :cascade do |t|
    t.boolean "correct", default: false
    t.datetime "created_at", precision: nil, null: false
    t.integer "question_id"
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "area_options", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.string "name"
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "booking_statuses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.datetime "updated_at", null: false
  end

  create_table "categories", id: :serial, force: :cascade do |t|
    t.integer "category_option_id"
    t.datetime "created_at", precision: nil, null: false
    t.string "name"
    t.integer "project_proposal_id"
    t.integer "repository_id"
    t.datetime "updated_at", precision: nil, null: false
    t.index ["category_option_id"], name: "index_categories_on_category_option_id"
    t.index ["repository_id"], name: "index_categories_on_repository_id"
  end

  create_table "category_options", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.string "name"
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "cc_moneys", id: :serial, force: :cascade do |t|
    t.integer "cc"
    t.datetime "created_at", precision: nil, null: false
    t.integer "discount_code_id"
    t.boolean "linked", default: true
    t.integer "order_id"
    t.integer "proficient_project_id"
    t.datetime "updated_at", precision: nil, null: false
    t.integer "user_id"
    t.integer "volunteer_task_id"
    t.index ["discount_code_id"], name: "index_cc_moneys_on_discount_code_id"
    t.index ["order_id"], name: "index_cc_moneys_on_order_id"
    t.index ["proficient_project_id"], name: "index_cc_moneys_on_proficient_project_id"
  end

  create_table "certifications", id: :serial, force: :cascade do |t|
    t.boolean "active", default: true
    t.datetime "created_at", precision: nil, null: false
    t.string "demotion_reason"
    t.bigint "demotion_staff_id"
    t.string "level"
    t.integer "training_session_id"
    t.datetime "updated_at", precision: nil, null: false
    t.integer "user_id"
    t.index ["demotion_staff_id"], name: "index_certifications_on_demotion_staff_id"
    t.index ["user_id"], name: "index_certifications_on_user_id"
  end

  create_table "chat_messages", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "is_read", default: false
    t.bigint "job_order_id"
    t.text "message"
    t.bigint "sender_id"
    t.datetime "updated_at", null: false
    t.index ["job_order_id"], name: "index_chat_messages_on_job_order_id"
    t.index ["sender_id"], name: "index_chat_messages_on_sender_id"
  end

  create_table "comments", id: :serial, force: :cascade do |t|
    t.text "content"
    t.datetime "created_at", precision: nil, null: false
    t.integer "repository_id"
    t.datetime "updated_at", precision: nil, null: false
    t.integer "upvote", default: 0
    t.integer "user_id"
    t.string "username"
    t.index ["repository_id"], name: "index_comments_on_repository_id"
    t.index ["user_id"], name: "index_comments_on_user_id"
  end

  create_table "contact_infos", force: :cascade do |t|
    t.string "address"
    t.datetime "created_at", null: false
    t.string "email"
    t.string "name"
    t.string "phone_number"
    t.boolean "show_hours"
    t.bigint "space_id"
    t.datetime "updated_at", null: false
    t.string "url"
    t.index ["space_id"], name: "index_contact_infos_on_space_id"
  end

  create_table "coupon_codes", force: :cascade do |t|
    t.integer "cc_cost"
    t.string "code"
    t.datetime "created_at", null: false
    t.integer "dollar_cost"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["user_id"], name: "index_coupon_codes_on_user_id"
  end

  create_table "course_names", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "design_day_schedules", force: :cascade do |t|
    t.bigint "design_day_id"
    t.time "end"
    t.integer "event_for"
    t.integer "ordering"
    t.time "start"
    t.string "title_en"
    t.string "title_fr"
    t.index ["design_day_id"], name: "index_design_day_schedules_on_design_day_id"
  end

  create_table "design_days", force: :cascade do |t|
    t.date "day"
    t.boolean "is_live"
    t.string "sheet_key"
    t.boolean "show_floorplans", default: true
  end

  create_table "discount_codes", id: :serial, force: :cascade do |t|
    t.string "code"
    t.datetime "created_at", precision: nil, null: false
    t.integer "price_rule_id"
    t.string "shopify_discount_code_id"
    t.datetime "updated_at", precision: nil, null: false
    t.integer "usage_count"
    t.integer "user_id"
    t.index ["price_rule_id"], name: "index_discount_codes_on_price_rule_id"
    t.index ["user_id"], name: "index_discount_codes_on_user_id"
  end

  create_table "drop_off_locations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "equipment", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.string "name"
    t.integer "repository_id"
    t.datetime "updated_at", precision: nil, null: false
    t.index ["repository_id"], name: "index_equipment_on_repository_id"
  end

  create_table "equipment_options", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.string "name"
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "event_assignments", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "event_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["event_id"], name: "index_event_assignments_on_event_id"
    t.index ["user_id"], name: "index_event_assignments_on_user_id"
  end

  create_table "events", force: :cascade do |t|
    t.bigint "course_name_id"
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.text "description"
    t.boolean "draft", default: true
    t.datetime "end_time"
    t.string "event_type"
    t.string "google_event_id"
    t.string "language"
    t.string "recurrence_rule"
    t.bigint "space_id"
    t.datetime "start_time"
    t.string "title"
    t.bigint "training_id"
    t.datetime "updated_at", null: false
    t.index ["course_name_id"], name: "index_events_on_course_name_id"
    t.index ["created_by_id"], name: "index_events_on_created_by_id"
    t.index ["space_id"], name: "index_events_on_space_id"
    t.index ["training_id"], name: "index_events_on_training_id"
  end

  create_table "exam_questions", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.integer "exam_id"
    t.integer "question_id"
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "exam_responses", id: :serial, force: :cascade do |t|
    t.integer "answer_id"
    t.boolean "correct"
    t.datetime "created_at", precision: nil, null: false
    t.integer "exam_question_id"
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "exams", id: :serial, force: :cascade do |t|
    t.string "category"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "expired_at", precision: nil
    t.integer "score"
    t.string "status", default: "not started"
    t.integer "training_session_id"
    t.datetime "updated_at", precision: nil, null: false
    t.integer "user_id"
  end

  create_table "faqs", force: :cascade do |t|
    t.text "body_en"
    t.text "body_fr"
    t.datetime "created_at", null: false
    t.integer "order"
    t.string "title_en"
    t.string "title_fr"
    t.datetime "updated_at", null: false
  end

  create_table "friendly_id_slugs", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil
    t.string "scope"
    t.string "slug", null: false
    t.integer "sluggable_id", null: false
    t.string "sluggable_type", limit: 50
    t.index ["slug", "sluggable_type", "scope"], name: "index_friendly_id_slugs_on_slug_and_sluggable_type_and_scope", unique: true
    t.index ["slug", "sluggable_type"], name: "index_friendly_id_slugs_on_slug_and_sluggable_type"
    t.index ["sluggable_id"], name: "index_friendly_id_slugs_on_sluggable_id"
    t.index ["sluggable_type"], name: "index_friendly_id_slugs_on_sluggable_type"
  end

  create_table "google_calendar_channels", force: :cascade do |t|
    t.string "channel_id", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "resource_id", null: false
    t.string "sync_token"
    t.datetime "updated_at", null: false
    t.index ["channel_id"], name: "index_google_calendar_channels_on_channel_id", unique: true
  end

  create_table "helps", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "gh_issue_number"
    t.datetime "updated_at", null: false
  end

  create_table "job_options", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.decimal "fee", precision: 10, scale: 2, null: false
    t.boolean "is_deleted", default: false, null: false
    t.boolean "is_job_wide", default: false, null: false
    t.string "name", null: false
    t.boolean "need_files", default: false, null: false
    t.datetime "updated_at", null: false
  end

  create_table "job_options_types", id: false, force: :cascade do |t|
    t.bigint "job_option_id", null: false
    t.bigint "job_type_id", null: false
    t.index ["job_option_id"], name: "index_job_options_types_on_job_option_id"
    t.index ["job_type_id"], name: "index_job_options_types_on_job_type_id"
  end

  create_table "job_order_messages", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "message"
    t.text "name"
    t.datetime "updated_at", null: false
  end

  create_table "job_order_options", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_option_id", null: false
    t.bigint "job_order_id", null: false
    t.datetime "updated_at", null: false
    t.index ["job_option_id"], name: "index_job_order_options_on_job_option_id"
    t.index ["job_order_id"], name: "index_job_order_options_on_job_order_id"
  end

  create_table "job_order_quote_options", force: :cascade do |t|
    t.integer "amount", null: false
    t.datetime "created_at", null: false
    t.bigint "job_option_id", null: false
    t.bigint "job_order_quote_id"
    t.datetime "updated_at", null: false
    t.index ["job_option_id"], name: "index_job_order_quote_options_on_job_option_id"
    t.index ["job_order_quote_id"], name: "index_job_order_quote_options_on_job_order_quote_id"
  end

  create_table "job_order_quote_services", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_order_quote_id"
    t.bigint "job_service_id", null: false
    t.decimal "per_unit", precision: 10, scale: 2, null: false
    t.decimal "quantity", precision: 10, scale: 2, null: false
    t.datetime "updated_at", null: false
    t.index ["job_order_quote_id"], name: "index_job_order_quote_services_on_job_order_quote_id"
    t.index ["job_service_id"], name: "index_job_order_quote_services_on_job_service_id"
  end

  create_table "job_order_quote_type_extras", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_order_quote_id"
    t.bigint "job_type_extra_id"
    t.decimal "price", precision: 10, scale: 2
    t.datetime "updated_at", null: false
    t.index ["job_order_quote_id"], name: "index_job_order_quote_type_extras_on_job_order_quote_id"
    t.index ["job_type_extra_id"], name: "index_job_order_quote_type_extras_on_job_type_extra_id"
  end

  create_table "job_order_quotes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.decimal "service_fee", precision: 10, scale: 2, null: false
    t.string "stripe_transaction_id"
    t.datetime "updated_at", null: false
  end

  create_table "job_order_statuses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_order_id"
    t.bigint "job_status_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["job_order_id"], name: "index_job_order_statuses_on_job_order_id"
    t.index ["job_status_id"], name: "index_job_order_statuses_on_job_status_id"
    t.index ["user_id"], name: "index_job_order_statuses_on_user_id"
  end

  create_table "job_orders", force: :cascade do |t|
    t.bigint "assigned_staff_id"
    t.text "comments"
    t.datetime "created_at", null: false
    t.boolean "is_deleted", default: false
    t.bigint "job_order_quote_id"
    t.bigint "job_service_group_id"
    t.bigint "job_type_id"
    t.string "shopify_draft_order_id"
    t.text "staff_comments"
    t.datetime "updated_at", null: false
    t.text "user_comments"
    t.bigint "user_id"
    t.index ["assigned_staff_id"], name: "index_job_orders_on_assigned_staff_id"
    t.index ["job_order_quote_id"], name: "index_job_orders_on_job_order_quote_id"
    t.index ["job_service_group_id"], name: "index_job_orders_on_job_service_group_id"
    t.index ["job_type_id"], name: "index_job_orders_on_job_type_id"
    t.index ["user_id"], name: "index_job_orders_on_user_id"
  end

  create_table "job_orders_services", id: false, force: :cascade do |t|
    t.bigint "job_order_id", null: false
    t.bigint "job_service_id", null: false
    t.index ["job_order_id"], name: "index_job_orders_services_on_job_order_id"
    t.index ["job_service_id"], name: "index_job_orders_services_on_job_service_id"
  end

  create_table "job_quote_line_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "description", null: false
    t.bigint "job_order_id", null: false
    t.decimal "price", precision: 10, scale: 2
    t.datetime "updated_at", null: false
    t.index ["job_order_id"], name: "index_job_quote_line_items_on_job_order_id"
  end

  create_table "job_service_groups", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "is_deleted", default: false, null: false
    t.bigint "job_type_id", null: false
    t.boolean "multiple", default: false
    t.string "name", null: false
    t.integer "text_field", default: 0
    t.datetime "updated_at", null: false
    t.index ["job_type_id"], name: "index_job_service_groups_on_job_type_id"
  end

  create_table "job_services", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.decimal "external_price", precision: 10, scale: 2
    t.decimal "internal_price", precision: 10, scale: 2
    t.boolean "is_deleted", default: false, null: false
    t.bigint "job_order_id"
    t.bigint "job_service_group_id", null: false
    t.string "name", null: false
    t.boolean "required", default: false, null: false
    t.string "unit"
    t.datetime "updated_at", null: false
    t.boolean "user_created", default: false
    t.index ["job_order_id"], name: "index_job_services_on_job_order_id"
    t.index ["job_service_group_id"], name: "index_job_services_on_job_service_group_id"
  end

  create_table "job_statuses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "description_fr"
    t.string "name", null: false
    t.string "name_fr"
    t.datetime "updated_at", null: false
  end

  create_table "job_task_options", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_option_id", null: false
    t.bigint "job_task_id", null: false
    t.datetime "updated_at", null: false
    t.index ["job_option_id"], name: "index_job_task_options_on_job_option_id"
    t.index ["job_task_id"], name: "index_job_task_options_on_job_task_id"
  end

  create_table "job_task_quote_options", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_option_id", null: false
    t.bigint "job_task_quote_id", null: false
    t.decimal "price", precision: 10, scale: 2
    t.datetime "updated_at", null: false
    t.index ["job_option_id"], name: "index_job_task_quote_options_on_job_option_id"
    t.index ["job_task_quote_id"], name: "index_job_task_quote_options_on_job_task_quote_id"
  end

  create_table "job_task_quotes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_task_id", null: false
    t.decimal "price", precision: 10, scale: 2
    t.decimal "service_price", precision: 10, scale: 2
    t.decimal "service_quantity", precision: 10, scale: 4, default: "1.0"
    t.datetime "updated_at", null: false
    t.index ["job_task_id"], name: "index_job_task_quotes_on_job_task_id"
  end

  create_table "job_tasks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_order_id", null: false
    t.bigint "job_service_id"
    t.bigint "job_type_id"
    t.string "title", default: ""
    t.datetime "updated_at", null: false
    t.index ["job_order_id"], name: "index_job_tasks_on_job_order_id"
    t.index ["job_service_id"], name: "index_job_tasks_on_job_service_id"
    t.index ["job_type_id"], name: "index_job_tasks_on_job_type_id"
  end

  create_table "job_type_extras", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "description"
    t.bigint "job_type_id"
    t.string "name"
    t.decimal "price", precision: 10, scale: 2
    t.datetime "updated_at", null: false
    t.index ["job_type_id"], name: "index_job_type_extras_on_job_type_id"
  end

  create_table "job_types", force: :cascade do |t|
    t.text "comments"
    t.datetime "created_at", null: false
    t.text "description"
    t.text "file_description"
    t.string "file_label", default: "File"
    t.boolean "is_deleted", default: false, null: false
    t.boolean "multiple_files", default: false, null: false
    t.string "name", null: false
    t.decimal "service_fee", precision: 10, scale: 2
    t.datetime "updated_at", null: false
  end

  create_table "key_certifications", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["user_id"], name: "index_key_certifications_on_user_id"
  end

  create_table "key_requests", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "emergency_contact"
    t.string "emergency_contact_phone_number"
    t.string "emergency_contact_relation"
    t.string "phone_number"
    t.string "question_1"
    t.string "question_10"
    t.string "question_11"
    t.string "question_12"
    t.string "question_13"
    t.string "question_14"
    t.string "question_2"
    t.string "question_3"
    t.string "question_4"
    t.string "question_5"
    t.string "question_6"
    t.string "question_7"
    t.string "question_8"
    t.string "question_9"
    t.boolean "read_agreement", default: false, null: false
    t.boolean "read_lab_rules", default: false, null: false
    t.boolean "read_policies", default: false, null: false
    t.bigint "space_id"
    t.integer "status"
    t.string "student_number"
    t.bigint "supervisor_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.integer "user_status"
    t.index ["space_id"], name: "index_key_requests_on_space_id"
    t.index ["supervisor_id"], name: "index_key_requests_on_supervisor_id"
    t.index ["user_id"], name: "index_key_requests_on_user_id"
  end

  create_table "key_transactions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.decimal "deposit_amount", precision: 5, scale: 2
    t.date "deposit_return_date"
    t.bigint "key_id"
    t.date "return_date"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["key_id"], name: "index_key_transactions_on_key_id"
    t.index ["user_id"], name: "index_key_transactions_on_user_id"
  end

  create_table "keys", force: :cascade do |t|
    t.string "additional_info", default: ""
    t.datetime "created_at", null: false
    t.string "custom_keycode"
    t.integer "key_type", default: 0
    t.string "number"
    t.bigint "space_id"
    t.integer "status", default: 0
    t.bigint "supervisor_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["space_id"], name: "index_keys_on_space_id"
    t.index ["supervisor_id"], name: "index_keys_on_supervisor_id"
    t.index ["user_id"], name: "index_keys_on_user_id"
  end

  create_table "lab_sessions", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.string "mac_address"
    t.datetime "sign_in_time", precision: nil
    t.datetime "sign_out_time", precision: nil
    t.integer "space_id"
    t.datetime "updated_at", precision: nil, null: false
    t.integer "user_id"
    t.index ["space_id"], name: "index_lab_sessions_on_space_id"
    t.index ["user_id"], name: "index_lab_sessions_on_user_id"
  end

  create_table "learning_module_tracks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "learning_module_id"
    t.jsonb "scorm_state"
    t.string "status", default: "In progress"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["learning_module_id"], name: "index_learning_module_tracks_on_learning_module_id"
    t.index ["user_id"], name: "index_learning_module_tracks_on_user_id"
  end

  create_table "learning_modules", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "level", default: "Beginner"
    t.integer "order"
    t.string "scorm_entry_point"
    t.string "scorm_prefix"
    t.integer "scorm_status", default: 0
    t.string "shortcut_name"
    t.string "subskill"
    t.string "title"
    t.integer "training_id"
    t.datetime "updated_at", null: false
    t.index ["shortcut_name"], name: "index_learning_modules_on_shortcut_name", unique: true
  end

  create_table "likes", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.integer "repository_id"
    t.datetime "updated_at", precision: nil, null: false
    t.integer "user_id"
    t.index ["repository_id"], name: "index_likes_on_repository_id"
    t.index ["user_id"], name: "index_likes_on_user_id"
  end

  create_table "locker_options", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
    t.string "value"
  end

  create_table "locker_rentals", force: :cascade do |t|
    t.datetime "cancelled_at"
    t.bigint "course_name_id"
    t.datetime "created_at", null: false
    t.bigint "decided_by_id"
    t.bigint "locker_id"
    t.string "notes"
    t.datetime "notified_of_cancellation_at"
    t.datetime "owned_until"
    t.datetime "paid_at"
    t.string "preferred_locker"
    t.bigint "preferred_locker_id"
    t.bigint "rented_by_id"
    t.string "requested_as"
    t.string "section_name"
    t.datetime "sent_to_checkout_at"
    t.string "shopify_draft_order_id"
    t.string "staff_notes"
    t.string "state"
    t.string "team_name"
    t.datetime "updated_at", null: false
    t.index ["course_name_id"], name: "index_locker_rentals_on_course_name_id"
    t.index ["decided_by_id"], name: "index_locker_rentals_on_decided_by_id"
    t.index ["locker_id"], name: "index_locker_rentals_on_locker_id"
    t.index ["preferred_locker_id"], name: "index_locker_rentals_on_preferred_locker_id"
    t.index ["rented_by_id"], name: "index_locker_rentals_on_rented_by_id"
  end

  create_table "locker_sizes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "shopify_gid"
    t.string "size"
    t.datetime "updated_at", null: false
  end

  create_table "lockers", force: :cascade do |t|
    t.boolean "available", default: true, null: false
    t.datetime "created_at", null: false
    t.bigint "locker_size_id"
    t.string "specifier"
    t.boolean "staff_only"
    t.datetime "updated_at", null: false
    t.index ["locker_size_id"], name: "index_lockers_on_locker_size_id"
    t.index ["specifier"], name: "index_lockers_on_specifier"
  end

  create_table "membership_tiers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "duration", null: false
    t.decimal "external_price", precision: 8, scale: 2, default: "0.0", null: false
    t.boolean "hidden", default: false, null: false
    t.decimal "internal_price", precision: 8, scale: 2, default: "0.0", null: false
    t.string "title_en", null: false
    t.string "title_fr", null: false
    t.datetime "updated_at", null: false
  end

  create_table "memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "end_date"
    t.bigint "membership_tier_id"
    t.string "shopify_draft_order_id"
    t.datetime "start_date"
    t.string "status", default: "paid"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["membership_tier_id"], name: "index_memberships_on_membership_tier_id"
    t.index ["user_id"], name: "index_memberships_on_user_id"
  end

  create_table "opening_hours", force: :cascade do |t|
    t.integer "closed_all_week", default: 0
    t.bigint "contact_info_id"
    t.datetime "created_at", null: false
    t.integer "friday_closed_all_day", default: 0
    t.time "friday_closing"
    t.time "friday_opening"
    t.integer "monday_closed_all_day", default: 0
    t.time "monday_closing"
    t.time "monday_opening"
    t.text "notes_en"
    t.text "notes_fr"
    t.integer "saturday_closed_all_day", default: 0
    t.time "saturday_closing"
    t.time "saturday_opening"
    t.integer "sunday_closed_all_day", default: 0
    t.time "sunday_closing"
    t.time "sunday_opening"
    t.string "target_en"
    t.string "target_fr"
    t.integer "thursday_closed_all_day", default: 0
    t.time "thursday_closing"
    t.time "thursday_opening"
    t.integer "tuesday_closed_all_day", default: 0
    t.time "tuesday_closing"
    t.time "tuesday_opening"
    t.datetime "updated_at", null: false
    t.integer "wednesday_closed_all_day", default: 0
    t.time "wednesday_closing"
    t.time "wednesday_opening"
    t.index ["contact_info_id"], name: "index_opening_hours_on_contact_info_id"
  end

  create_table "order_items", id: :serial, force: :cascade do |t|
    t.text "admin_comments", default: ""
    t.datetime "created_at", precision: nil, null: false
    t.integer "order_id"
    t.integer "proficient_project_id"
    t.integer "quantity"
    t.string "status", default: "In progress"
    t.decimal "total_price", precision: 12, scale: 3
    t.decimal "unit_price", precision: 12, scale: 3
    t.datetime "updated_at", precision: nil, null: false
    t.text "user_comments", default: ""
  end

  create_table "order_statuses", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.string "name"
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "orders", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.integer "order_status_id"
    t.decimal "subtotal", precision: 12, scale: 3
    t.decimal "total", precision: 12, scale: 3
    t.datetime "updated_at", precision: nil, null: false
    t.integer "user_id"
  end

  create_table "photos", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.integer "height"
    t.string "image_content_type"
    t.string "image_file_name"
    t.integer "image_file_size"
    t.datetime "image_updated_at", precision: nil
    t.integer "learning_module_id"
    t.integer "position", default: 0, null: false
    t.integer "proficient_project_id"
    t.integer "project_proposal_id"
    t.integer "repository_id"
    t.datetime "updated_at", precision: nil, null: false
    t.integer "volunteer_task_id"
    t.integer "width"
    t.index ["repository_id"], name: "index_photos_on_repository_id"
  end

  create_table "pi_readers", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.string "pi_location"
    t.string "pi_mac_address"
    t.integer "space_id"
    t.datetime "updated_at", precision: nil, null: false
    t.index ["space_id"], name: "index_pi_readers_on_space_id"
  end

  create_table "popular_hours", force: :cascade do |t|
    t.integer "count", default: 0
    t.datetime "created_at", null: false
    t.integer "day"
    t.integer "hour"
    t.float "mean", default: 0.0
    t.float "previous_mean", default: 0.0
    t.bigint "space_id"
    t.datetime "updated_at", null: false
    t.index ["space_id"], name: "index_popular_hours_on_space_id"
  end

  create_table "price_rules", id: :serial, force: :cascade do |t|
    t.integer "cc"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "expired_at", precision: nil
    t.string "shopify_price_rule_id"
    t.string "title"
    t.datetime "updated_at", precision: nil, null: false
    t.integer "usage_limit"
    t.integer "value"
  end

  create_table "print_orders", id: :serial, force: :cascade do |t|
    t.boolean "approved"
    t.boolean "clean_part"
    t.text "comments"
    t.string "comments_box"
    t.string "comments_for_staff"
    t.datetime "created_at", precision: nil, null: false
    t.boolean "expedited"
    t.string "file_content_type"
    t.string "file_file_name"
    t.integer "file_file_size"
    t.datetime "file_updated_at", precision: nil
    t.string "final_file_content_type"
    t.string "final_file_file_name"
    t.integer "final_file_file_size"
    t.datetime "final_file_updated_at", precision: nil
    t.float "grams"
    t.float "grams_carbonfiber", default: 0.0
    t.float "grams_fiberglass", default: 0.0
    t.float "hours"
    t.text "material"
    t.float "material_cost"
    t.integer "order_type", default: 0
    t.boolean "payed"
    t.boolean "picked_up"
    t.float "price_per_gram"
    t.float "price_per_gram_carbonfiber", default: 0.0
    t.float "price_per_gram_fiberglass", default: 0.0
    t.float "price_per_hour"
    t.boolean "printed"
    t.float "quote"
    t.float "service_charge"
    t.boolean "sst"
    t.text "staff_comments"
    t.integer "staff_id"
    t.datetime "timestamp_approved", precision: nil
    t.datetime "timestamp_printed", precision: nil
    t.datetime "updated_at", precision: nil, null: false
    t.boolean "user_approval"
    t.integer "user_id"
  end

  create_table "printer_issues", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "description"
    t.bigint "printer_id", null: false
    t.bigint "reporter_id", null: false
    t.string "summary", null: false
    t.datetime "updated_at", null: false
    t.index ["printer_id"], name: "index_printer_issues_on_printer_id"
    t.index ["reporter_id"], name: "index_printer_issues_on_reporter_id"
  end

  create_table "printer_sessions", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.boolean "in_use", default: false
    t.integer "printer_id"
    t.datetime "updated_at", precision: nil, null: false
    t.integer "user_id"
  end

  create_table "printer_types", force: :cascade do |t|
    t.boolean "available", default: true
    t.datetime "created_at", null: false
    t.string "name"
    t.string "short_form", default: ""
    t.datetime "updated_at", null: false
  end

  create_table "printers", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.boolean "maintenance", default: false
    t.string "number"
    t.bigint "printer_type_id"
    t.datetime "updated_at", precision: nil, null: false
    t.index ["printer_type_id"], name: "index_printers_on_printer_type_id"
  end

  create_table "proficient_project_sessions", force: :cascade do |t|
    t.bigint "certification_id"
    t.datetime "created_at", null: false
    t.string "level"
    t.bigint "proficient_project_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["certification_id"], name: "index_proficient_project_sessions_on_certification_id"
    t.index ["proficient_project_id"], name: "index_proficient_project_sessions_on_proficient_project_id"
    t.index ["user_id"], name: "index_proficient_project_sessions_on_user_id"
  end

  create_table "proficient_projects", id: :serial, force: :cascade do |t|
    t.integer "cc", default: 0
    t.datetime "created_at", precision: nil, null: false
    t.text "description"
    t.bigint "drop_off_location_id"
    t.boolean "has_project_kit"
    t.boolean "is_virtual", default: false
    t.string "level", default: "Beginner"
    t.string "title"
    t.integer "training_id"
    t.datetime "updated_at", precision: nil, null: false
    t.index ["drop_off_location_id"], name: "index_proficient_projects_on_drop_off_location_id"
  end

  create_table "proficient_projects_users", id: false, force: :cascade do |t|
    t.integer "proficient_project_id", null: false
    t.integer "user_id", null: false
  end

  create_table "programs", id: :serial, force: :cascade do |t|
    t.boolean "active", default: true
    t.datetime "created_at", precision: nil, null: false
    t.string "program_type"
    t.datetime "updated_at", precision: nil, null: false
    t.integer "user_id"
  end

  create_table "project_joins", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.integer "project_proposal_id"
    t.datetime "updated_at", precision: nil, null: false
    t.integer "user_id"
  end

  create_table "project_kits", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "delivered", default: false
    t.bigint "learning_module_id"
    t.string "name"
    t.bigint "proficient_project_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["learning_module_id"], name: "index_project_kits_on_learning_module_id"
    t.index ["proficient_project_id"], name: "index_project_kits_on_proficient_project_id"
    t.index ["user_id"], name: "index_project_kits_on_user_id"
  end

  create_table "project_proposals", id: :serial, force: :cascade do |t|
    t.integer "admin_id"
    t.integer "approved"
    t.string "area", default: [], array: true
    t.string "client"
    t.string "client_background"
    t.string "client_interest"
    t.string "client_type"
    t.datetime "created_at", precision: nil, null: false
    t.text "description"
    t.string "email"
    t.text "equipments", default: "Not informed / Pas informé"
    t.bigint "linked_project_proposal_id"
    t.string "past_experiences"
    t.integer "project_cost"
    t.string "project_type"
    t.integer "prototype_cost"
    t.integer "season"
    t.string "slug"
    t.string "supervisor_background"
    t.string "title"
    t.datetime "updated_at", precision: nil, null: false
    t.integer "user_id"
    t.string "username"
    t.integer "year"
    t.string "youtube_link"
    t.index ["linked_project_proposal_id"], name: "index_project_proposals_on_linked_project_proposal_id"
    t.index ["title"], name: "index_project_proposals_on_title", opclass: :gin_trgm_ops, using: :gin
    t.index ["year", "season"], name: "index_project_proposals_on_year_and_season"
  end

  create_table "project_requirements", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.integer "proficient_project_id"
    t.integer "required_project_id"
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "questions", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.text "description"
    t.string "image_content_type"
    t.string "image_file_name"
    t.integer "image_file_size"
    t.datetime "image_updated_at", precision: nil
    t.string "level", default: "Beginner"
    t.integer "training_id"
    t.datetime "updated_at", precision: nil, null: false
    t.integer "user_id"
  end

  create_table "questions_trainings", id: false, force: :cascade do |t|
    t.bigint "question_id", null: false
    t.bigint "training_id", null: false
  end

  create_table "quick_access_links", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.string "path"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_quick_access_links_on_user_id"
  end

  create_table "recurring_bookings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "repo_files", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.string "file_content_type"
    t.string "file_file_name"
    t.integer "file_file_size"
    t.datetime "file_updated_at", precision: nil
    t.integer "learning_module_id"
    t.integer "proficient_project_id"
    t.integer "project_proposal_id"
    t.integer "repository_id"
    t.datetime "updated_at", precision: nil, null: false
    t.index ["repository_id"], name: "index_repo_files_on_repository_id"
  end

  create_table "repositories", id: :serial, force: :cascade do |t|
    t.string "category"
    t.datetime "created_at", precision: nil, null: false
    t.boolean "deleted"
    t.string "description"
    t.boolean "featured", default: false
    t.string "github"
    t.string "github_url"
    t.string "license"
    t.integer "like", default: 0
    t.integer "make", default: 0
    t.integer "make_id"
    t.string "password"
    t.integer "project_proposal_id"
    t.string "share_type"
    t.string "slug"
    t.string "title"
    t.datetime "updated_at", precision: nil, null: false
    t.integer "user_id"
    t.string "youtube_link"
    t.index ["category"], name: "index_repositories_on_category", opclass: :gin_trgm_ops, using: :gin
    t.index ["description"], name: "index_repositories_on_description", opclass: :gin_trgm_ops, using: :gin
    t.index ["title"], name: "index_repositories_on_title", opclass: :gin_trgm_ops, using: :gin
    t.index ["user_id"], name: "index_repositories_on_user_id"
  end

  create_table "repositories_users", id: false, force: :cascade do |t|
    t.integer "repository_id", null: false
    t.integer "user_id", null: false
  end

  create_table "require_trainings", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.integer "training_id"
    t.datetime "updated_at", precision: nil, null: false
    t.integer "volunteer_task_id"
  end

  create_table "rfids", id: :serial, force: :cascade do |t|
    t.string "card_number"
    t.datetime "created_at", precision: nil, null: false
    t.string "mac_address"
    t.datetime "updated_at", precision: nil, null: false
    t.integer "user_id"
    t.index ["user_id"], name: "index_rfids_on_user_id"
  end

  create_table "settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.string "value"
    t.index ["key"], name: "index_settings_on_key", unique: true
  end

  create_table "shadowing_hours", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "end_time", precision: nil
    t.string "event_id"
    t.bigint "space_id"
    t.datetime "start_time", precision: nil
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["space_id"], name: "index_shadowing_hours_on_space_id"
    t.index ["user_id"], name: "index_shadowing_hours_on_user_id"
  end

  create_table "shifts", force: :cascade do |t|
    t.string "course"
    t.datetime "created_at", null: false
    t.datetime "end_datetime", precision: nil
    t.string "google_event_id"
    t.string "language"
    t.boolean "pending", default: true
    t.text "reason"
    t.bigint "space_id"
    t.datetime "start_datetime", precision: nil
    t.bigint "training_id"
    t.datetime "updated_at", null: false
    t.index ["space_id"], name: "index_shifts_on_space_id"
    t.index ["training_id"], name: "index_shifts_on_training_id"
  end

  create_table "shifts_users", id: false, force: :cascade do |t|
    t.bigint "shift_id", null: false
    t.bigint "user_id", null: false
    t.index ["shift_id"], name: "index_shifts_users_on_shift_id"
    t.index ["user_id"], name: "index_shifts_users_on_user_id"
  end

  create_table "skills", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "name"
    t.datetime "updated_at", null: false
  end

  create_table "space_manager_joins", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "space_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["space_id"], name: "index_space_manager_joins_on_space_id"
    t.index ["user_id"], name: "index_space_manager_joins_on_user_id"
  end

  create_table "spaces", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.integer "destroy_admin_id"
    t.string "keycode", default: ""
    t.integer "max_capacity"
    t.string "name"
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "spaces_trainings", id: false, force: :cascade do |t|
    t.integer "space_id", null: false
    t.integer "training_id", null: false
  end

  create_table "staff_availabilities", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "day"
    t.datetime "end_datetime"
    t.time "end_time"
    t.boolean "recurring", default: true
    t.datetime "start_datetime"
    t.time "start_time"
    t.bigint "time_period_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["time_period_id"], name: "index_staff_availabilities_on_time_period_id"
    t.index ["user_id"], name: "index_staff_availabilities_on_user_id"
  end

  create_table "staff_availability_exceptions", force: :cascade do |t|
    t.integer "covers", default: 0
    t.bigint "staff_availability_id"
    t.datetime "start_at"
    t.index ["staff_availability_id"], name: "index_staff_availability_exceptions_on_staff_availability_id"
  end

  create_table "staff_external_unavailabilities", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ics_url"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_staff_external_unavailabilities_on_user_id"
  end

  create_table "staff_needed_calendars", force: :cascade do |t|
    t.string "calendar_url", null: false
    t.string "color"
    t.datetime "created_at", null: false
    t.string "name"
    t.string "role"
    t.bigint "space_id"
    t.datetime "updated_at", null: false
    t.index ["space_id"], name: "index_staff_needed_calendars_on_space_id"
    t.index ["space_id"], name: "index_unique_open_hours_per_space", unique: true, where: "((role)::text = 'open_hours'::text)"
  end

  create_table "staff_spaces", force: :cascade do |t|
    t.string "color"
    t.datetime "created_at", null: false
    t.bigint "space_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["space_id"], name: "index_staff_spaces_on_space_id"
    t.index ["user_id"], name: "index_staff_spaces_on_user_id"
  end

  create_table "staff_unavailabilities", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "end_time"
    t.string "recurrence_rule"
    t.datetime "start_time"
    t.string "title"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["user_id"], name: "index_staff_unavailabilities_on_user_id"
  end

  create_table "sub_space_booking_statuses", force: :cascade do |t|
    t.bigint "booking_status_id"
    t.datetime "created_at", null: false
    t.bigint "sub_space_booking_id"
    t.datetime "updated_at", null: false
    t.index ["booking_status_id"], name: "index_sub_space_booking_statuses_on_booking_status_id"
    t.index ["sub_space_booking_id"], name: "index_sub_space_booking_statuses_on_sub_space_booking_id"
  end

  create_table "sub_space_bookings", force: :cascade do |t|
    t.datetime "approved_at"
    t.bigint "approved_by_id"
    t.boolean "blocking", default: false
    t.datetime "created_at", null: false
    t.string "description"
    t.datetime "end_time", precision: nil
    t.string "google_booking_id"
    t.string "name"
    t.boolean "public", default: false
    t.bigint "recurring_booking_id"
    t.datetime "start_time", precision: nil
    t.bigint "sub_space_booking_status_id"
    t.bigint "sub_space_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["approved_by_id"], name: "index_sub_space_bookings_on_approved_by_id"
    t.index ["recurring_booking_id"], name: "index_sub_space_bookings_on_recurring_booking_id"
    t.index ["sub_space_booking_status_id"], name: "index_sub_space_bookings_on_sub_space_booking_status_id"
    t.index ["sub_space_id"], name: "index_sub_space_bookings_on_sub_space_id"
    t.index ["user_id"], name: "index_sub_space_bookings_on_user_id"
  end

  create_table "sub_spaces", force: :cascade do |t|
    t.boolean "approval_required", default: false
    t.datetime "created_at", null: false
    t.boolean "default_public", default: false
    t.integer "max_automatic_approval_hour"
    t.integer "maximum_booking_duration"
    t.integer "maximum_booking_hours_per_week"
    t.string "name"
    t.bigint "space_id"
    t.datetime "updated_at", null: false
    t.index ["space_id"], name: "index_sub_spaces_on_space_id"
  end

  create_table "tap_box_logs", force: :cascade do |t|
    t.string "card_number"
    t.datetime "created_at", null: false
    t.json "details", default: {}
    t.string "event_type", null: false
    t.string "mac_address"
    t.text "message", null: false
    t.bigint "space_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["card_number"], name: "index_tap_box_logs_on_card_number"
    t.index ["created_at"], name: "index_tap_box_logs_on_created_at"
    t.index ["event_type"], name: "index_tap_box_logs_on_event_type"
    t.index ["space_id"], name: "index_tap_box_logs_on_space_id"
    t.index ["user_id"], name: "index_tap_box_logs_on_user_id"
  end

  create_table "team_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "role", default: 0
    t.bigint "team_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["team_id"], name: "index_team_memberships_on_team_id"
    t.index ["user_id"], name: "index_team_memberships_on_user_id"
  end

  create_table "teams", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "time_periods", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "end_date"
    t.string "name"
    t.date "start_date"
    t.datetime "updated_at", null: false
  end

  create_table "training_requirements", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "level"
    t.bigint "proficient_project_id"
    t.bigint "training_id"
    t.datetime "updated_at", null: false
    t.index ["proficient_project_id"], name: "index_training_requirements_on_proficient_project_id"
    t.index ["training_id"], name: "index_training_requirements_on_training_id"
  end

  create_table "training_sessions", id: :serial, force: :cascade do |t|
    t.string "course"
    t.integer "course_name_id"
    t.datetime "created_at", precision: nil, null: false
    t.string "level", default: "Beginner"
    t.integer "space_id"
    t.integer "training_id"
    t.datetime "updated_at", precision: nil, null: false
    t.integer "user_id"
    t.index ["training_id"], name: "index_training_sessions_on_training_id"
    t.index ["user_id"], name: "index_training_sessions_on_user_id"
  end

  create_table "training_sessions_users", id: false, force: :cascade do |t|
    t.integer "training_session_id"
    t.integer "user_id"
    t.index ["training_session_id"], name: "index_training_sessions_users_on_training_session_id"
    t.index ["user_id"], name: "index_training_sessions_users_on_user_id"
  end

  create_table "trainings", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.string "description_en"
    t.string "description_fr"
    t.boolean "has_badge", default: true
    t.string "list_of_skills_en"
    t.string "list_of_skills_fr"
    t.string "name_en"
    t.string "name_fr"
    t.bigint "skill_id"
    t.integer "space_id"
    t.datetime "updated_at", precision: nil, null: false
    t.index ["skill_id"], name: "index_trainings_on_skill_id"
    t.index ["space_id"], name: "index_trainings_on_space_id"
  end

  create_table "uni_programs", id: false, force: :cascade do |t|
    t.string "department", null: false
    t.string "faculty", null: false
    t.string "level", null: false
    t.string "program", null: false
    t.index ["program"], name: "index_uni_programs_on_program"
  end

  create_table "upvotes", id: :serial, force: :cascade do |t|
    t.integer "comment_id"
    t.datetime "created_at", precision: nil, null: false
    t.boolean "downvote"
    t.datetime "updated_at", precision: nil, null: false
    t.integer "user_id"
    t.index ["comment_id"], name: "index_upvotes_on_comment_id"
    t.index ["user_id"], name: "index_upvotes_on_user_id"
  end

  create_table "user_booking_approvals", force: :cascade do |t|
    t.boolean "approved"
    t.string "comments"
    t.datetime "created_at", null: false
    t.date "date"
    t.string "identity"
    t.bigint "staff_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["staff_id"], name: "index_user_booking_approvals_on_staff_id"
    t.index ["user_id"], name: "index_user_booking_approvals_on_user_id"
  end

  create_table "users", id: :serial, force: :cascade do |t|
    t.string "access_token"
    t.boolean "active", default: true
    t.integer "auth_attempts", default: 0
    t.string "avatar_content_type"
    t.string "avatar_file_name"
    t.integer "avatar_file_size"
    t.datetime "avatar_updated_at", precision: nil
    t.boolean "booking_approval", default: false
    t.boolean "confirmed", default: false
    t.datetime "created_at", precision: nil, null: false
    t.boolean "deleted"
    t.text "description"
    t.citext "email"
    t.string "faculty"
    t.string "flag_message", default: ""
    t.boolean "flagged"
    t.string "gender"
    t.string "how_heard_about_us"
    t.string "identity"
    t.datetime "last_seen_at", precision: nil
    t.datetime "last_signed_in_time", precision: nil
    t.boolean "locked", default: false
    t.datetime "locked_until", precision: nil
    t.string "name"
    t.string "password"
    t.string "program"
    t.boolean "read_and_accepted_waiver_form", default: false
    t.integer "reputation", default: 0
    t.string "role", default: "regular_user"
    t.bigint "space_id"
    t.string "student_id"
    t.boolean "terms_and_conditions"
    t.datetime "updated_at", precision: nil, null: false
    t.string "url"
    t.string "use"
    t.citext "username"
    t.integer "wallet", default: 0
    t.string "year_of_study"
    t.index "lower((email)::text)", name: "index_users_on_lowercase_email", unique: true
    t.index "lower((username)::text)", name: "index_users_on_lowercase_username", unique: true
    t.index ["name"], name: "index_users_on_name", opclass: :gin_trgm_ops, using: :gin
    t.index ["space_id"], name: "index_users_on_space_id"
    t.index ["username"], name: "index_users_on_username", opclass: :gin_trgm_ops, using: :gin
  end

  create_table "videos", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.bigint "learning_module_id"
    t.boolean "processed", default: false, null: false
    t.integer "proficient_project_id"
    t.datetime "updated_at", precision: nil, null: false
    t.index ["learning_module_id"], name: "index_videos_on_learning_module_id"
    t.index ["proficient_project_id"], name: "index_videos_on_proficient_project_id"
  end

  create_table "volunteer_hours", id: :serial, force: :cascade do |t|
    t.boolean "approval"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "date_of_task", precision: nil
    t.decimal "total_time", precision: 9, scale: 2, default: "0.0"
    t.datetime "updated_at", precision: nil, null: false
    t.integer "user_id", null: false
    t.integer "volunteer_task_id", null: false
  end

  create_table "volunteer_task_joins", id: :serial, force: :cascade do |t|
    t.boolean "active", default: true
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "user_id"
    t.string "user_type", default: "Volunteer"
    t.integer "volunteer_task_id"
  end

  create_table "volunteer_task_requests", id: :serial, force: :cascade do |t|
    t.boolean "approval"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "user_id"
    t.integer "volunteer_task_id"
  end

  create_table "volunteer_tasks", id: :serial, force: :cascade do |t|
    t.string "category", default: "Other"
    t.integer "cc", default: 0
    t.datetime "created_at", precision: nil, null: false
    t.text "description", default: ""
    t.decimal "hours", precision: 5, scale: 2, default: "0.0"
    t.integer "joins", default: 1
    t.integer "space_id"
    t.string "status", default: "open"
    t.string "title", default: ""
    t.datetime "updated_at", precision: nil, null: false
    t.integer "user_id"
  end

  create_table "walk_in_safety_sheets", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "emergency_contact_name"
    t.string "emergency_contact_telephone"
    t.string "guardian_signature"
    t.string "guardian_telephone_at_home"
    t.string "guardian_telephone_at_work"
    t.boolean "is_minor"
    t.string "minor_participant_name"
    t.string "participant_signature"
    t.string "participant_telephone_at_home"
    t.bigint "space_id"
    t.string "supervisor_contacts"
    t.string "supervisor_names"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["space_id"], name: "index_walk_in_safety_sheets_on_space_id"
    t.index ["user_id", "space_id"], name: "index_walk_in_safety_sheets_on_user_id_and_space_id", unique: true
    t.index ["user_id"], name: "index_walk_in_safety_sheets_on_user_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "announcement_dismisses", "announcements"
  add_foreign_key "announcement_dismisses", "users"
  add_foreign_key "categories", "category_options"
  add_foreign_key "categories", "repositories"
  add_foreign_key "cc_moneys", "discount_codes"
  add_foreign_key "cc_moneys", "orders"
  add_foreign_key "cc_moneys", "proficient_projects"
  add_foreign_key "certifications", "users"
  add_foreign_key "certifications", "users", column: "demotion_staff_id"
  add_foreign_key "chat_messages", "job_orders"
  add_foreign_key "chat_messages", "users", column: "sender_id"
  add_foreign_key "comments", "repositories"
  add_foreign_key "comments", "users"
  add_foreign_key "contact_infos", "spaces"
  add_foreign_key "coupon_codes", "users"
  add_foreign_key "discount_codes", "price_rules"
  add_foreign_key "discount_codes", "users"
  add_foreign_key "equipment", "repositories"
  add_foreign_key "event_assignments", "events"
  add_foreign_key "event_assignments", "users"
  add_foreign_key "events", "course_names", on_delete: :nullify
  add_foreign_key "events", "spaces"
  add_foreign_key "events", "trainings", on_delete: :nullify
  add_foreign_key "events", "users", column: "created_by_id"
  add_foreign_key "job_order_options", "job_options"
  add_foreign_key "job_order_options", "job_orders"
  add_foreign_key "job_order_quote_options", "job_options"
  add_foreign_key "job_order_quote_options", "job_order_quotes"
  add_foreign_key "job_order_quote_services", "job_order_quotes"
  add_foreign_key "job_order_quote_services", "job_services"
  add_foreign_key "job_order_quote_type_extras", "job_order_quotes"
  add_foreign_key "job_order_quote_type_extras", "job_type_extras"
  add_foreign_key "job_order_statuses", "job_orders"
  add_foreign_key "job_order_statuses", "job_statuses"
  add_foreign_key "job_order_statuses", "users"
  add_foreign_key "job_orders", "job_service_groups"
  add_foreign_key "job_orders", "users", column: "assigned_staff_id"
  add_foreign_key "job_quote_line_items", "job_orders"
  add_foreign_key "job_service_groups", "job_types"
  add_foreign_key "job_services", "job_orders"
  add_foreign_key "job_services", "job_service_groups"
  add_foreign_key "job_task_options", "job_options"
  add_foreign_key "job_task_options", "job_tasks"
  add_foreign_key "job_task_quote_options", "job_options"
  add_foreign_key "job_task_quote_options", "job_task_quotes"
  add_foreign_key "job_task_quotes", "job_tasks"
  add_foreign_key "job_tasks", "job_orders"
  add_foreign_key "job_tasks", "job_services"
  add_foreign_key "job_tasks", "job_types"
  add_foreign_key "job_type_extras", "job_types"
  add_foreign_key "lab_sessions", "spaces"
  add_foreign_key "learning_module_tracks", "learning_modules"
  add_foreign_key "learning_module_tracks", "users"
  add_foreign_key "likes", "repositories"
  add_foreign_key "likes", "users"
  add_foreign_key "locker_rentals", "lockers"
  add_foreign_key "locker_rentals", "users", column: "decided_by_id"
  add_foreign_key "locker_rentals", "users", column: "rented_by_id"
  add_foreign_key "memberships", "membership_tiers"
  add_foreign_key "memberships", "users"
  add_foreign_key "order_items", "orders"
  add_foreign_key "order_items", "proficient_projects"
  add_foreign_key "orders", "order_statuses"
  add_foreign_key "photos", "repositories"
  add_foreign_key "pi_readers", "spaces"
  add_foreign_key "popular_hours", "spaces"
  add_foreign_key "printer_issues", "printers"
  add_foreign_key "printer_issues", "users", column: "reporter_id"
  add_foreign_key "printers", "printer_types"
  add_foreign_key "proficient_project_sessions", "certifications"
  add_foreign_key "proficient_project_sessions", "proficient_projects"
  add_foreign_key "proficient_project_sessions", "users"
  add_foreign_key "proficient_projects", "drop_off_locations"
  add_foreign_key "project_kits", "learning_modules"
  add_foreign_key "project_kits", "proficient_projects"
  add_foreign_key "project_kits", "users"
  add_foreign_key "quick_access_links", "users"
  add_foreign_key "repo_files", "repositories"
  add_foreign_key "repositories", "users"
  add_foreign_key "rfids", "users"
  add_foreign_key "shadowing_hours", "spaces"
  add_foreign_key "shadowing_hours", "users"
  add_foreign_key "shifts", "spaces"
  add_foreign_key "shifts", "trainings"
  add_foreign_key "staff_availabilities", "time_periods"
  add_foreign_key "staff_availabilities", "users"
  add_foreign_key "staff_external_unavailabilities", "users"
  add_foreign_key "staff_needed_calendars", "spaces"
  add_foreign_key "staff_spaces", "spaces"
  add_foreign_key "staff_spaces", "users"
  add_foreign_key "staff_unavailabilities", "users"
  add_foreign_key "sub_space_booking_statuses", "booking_statuses"
  add_foreign_key "sub_space_booking_statuses", "sub_space_bookings", on_delete: :cascade
  add_foreign_key "sub_space_bookings", "recurring_bookings"
  add_foreign_key "sub_space_bookings", "sub_space_booking_statuses"
  add_foreign_key "sub_space_bookings", "sub_spaces", on_delete: :cascade
  add_foreign_key "sub_space_bookings", "users"
  add_foreign_key "sub_space_bookings", "users", column: "approved_by_id"
  add_foreign_key "sub_spaces", "spaces"
  add_foreign_key "tap_box_logs", "spaces"
  add_foreign_key "tap_box_logs", "users"
  add_foreign_key "training_requirements", "proficient_projects"
  add_foreign_key "training_requirements", "trainings"
  add_foreign_key "training_sessions", "trainings"
  add_foreign_key "training_sessions", "users"
  add_foreign_key "trainings", "skills"
  add_foreign_key "trainings", "spaces"
  add_foreign_key "upvotes", "comments"
  add_foreign_key "upvotes", "users"
  add_foreign_key "user_booking_approvals", "users"
  add_foreign_key "user_booking_approvals", "users", column: "staff_id"
  add_foreign_key "users", "spaces"
  add_foreign_key "videos", "learning_modules"
  add_foreign_key "videos", "proficient_projects"
  add_foreign_key "walk_in_safety_sheets", "users"
end
