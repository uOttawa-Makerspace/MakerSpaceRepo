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

ActiveRecord::Schema[7.2].define(version: 2025_06_13_150014) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"
  enable_extension "unaccent"

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
    t.datetime "created_at", precision: nil, null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", precision: nil, null: false
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
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["announcement_id"], name: "index_announcement_dismisses_on_announcement_id"
    t.index ["user_id"], name: "index_announcement_dismisses_on_user_id"
  end

  create_table "announcements", id: :serial, force: :cascade do |t|
    t.text "description"
    t.string "public_goal"
    t.integer "user_id"
    t.boolean "active", default: true
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.date "end_date"
  end

  create_table "answers", id: :serial, force: :cascade do |t|
    t.integer "question_id"
    t.boolean "correct", default: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "area_options", id: :serial, force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "booking_statuses", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "categories", id: :serial, force: :cascade do |t|
    t.integer "repository_id"
    t.string "name"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "category_option_id"
    t.integer "project_proposal_id"
    t.index ["category_option_id"], name: "index_categories_on_category_option_id"
    t.index ["repository_id"], name: "index_categories_on_repository_id"
  end

  create_table "category_options", id: :serial, force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "cc_moneys", id: :serial, force: :cascade do |t|
    t.integer "user_id"
    t.integer "volunteer_task_id"
    t.integer "cc"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "proficient_project_id"
    t.integer "order_id"
    t.integer "discount_code_id"
    t.boolean "linked", default: true
    t.index ["discount_code_id"], name: "index_cc_moneys_on_discount_code_id"
    t.index ["order_id"], name: "index_cc_moneys_on_order_id"
    t.index ["proficient_project_id"], name: "index_cc_moneys_on_proficient_project_id"
  end

  create_table "certifications", id: :serial, force: :cascade do |t|
    t.integer "user_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "training_session_id"
    t.boolean "active", default: true
    t.string "demotion_reason"
    t.bigint "demotion_staff_id"
    t.string "level"
    t.index ["demotion_staff_id"], name: "index_certifications_on_demotion_staff_id"
    t.index ["user_id"], name: "index_certifications_on_user_id"
  end

  create_table "comments", id: :serial, force: :cascade do |t|
    t.integer "user_id"
    t.integer "repository_id"
    t.text "content"
    t.integer "upvote", default: 0
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "username"
    t.index ["repository_id"], name: "index_comments_on_repository_id"
    t.index ["user_id"], name: "index_comments_on_user_id"
  end

  create_table "contact_infos", force: :cascade do |t|
    t.string "name"
    t.string "email"
    t.string "address"
    t.string "phone_number"
    t.string "url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "show_hours"
    t.bigint "space_id"
    t.index ["space_id"], name: "index_contact_infos_on_space_id"
  end

  create_table "coupon_codes", force: :cascade do |t|
    t.string "code"
    t.integer "cc_cost"
    t.integer "dollar_cost"
    t.bigint "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_coupon_codes_on_user_id"
  end

  create_table "course_names", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "design_day_schedules", force: :cascade do |t|
    t.bigint "design_day_id"
    t.time "start"
    t.time "end"
    t.integer "ordering"
    t.string "title_en"
    t.string "title_fr"
    t.integer "event_for"
    t.index ["design_day_id"], name: "index_design_day_schedules_on_design_day_id"
  end

  create_table "design_days", force: :cascade do |t|
    t.date "day"
    t.string "sheet_key"
    t.boolean "is_live"
  end

  create_table "discount_codes", id: :serial, force: :cascade do |t|
    t.integer "price_rule_id"
    t.integer "user_id"
    t.string "shopify_discount_code_id"
    t.string "code"
    t.integer "usage_count"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["price_rule_id"], name: "index_discount_codes_on_price_rule_id"
    t.index ["user_id"], name: "index_discount_codes_on_user_id"
  end

  create_table "drop_off_locations", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "equipment", id: :serial, force: :cascade do |t|
    t.integer "repository_id"
    t.string "name"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["repository_id"], name: "index_equipment_on_repository_id"
  end

  create_table "equipment_options", id: :serial, force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "exam_questions", id: :serial, force: :cascade do |t|
    t.integer "exam_id"
    t.integer "question_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "exam_responses", id: :serial, force: :cascade do |t|
    t.integer "exam_question_id"
    t.integer "answer_id"
    t.boolean "correct"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "exams", id: :serial, force: :cascade do |t|
    t.integer "user_id"
    t.string "category"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "status", default: "not started"
    t.integer "score"
    t.integer "training_session_id"
    t.datetime "expired_at", precision: nil
  end

  create_table "faqs", force: :cascade do |t|
    t.string "title_en"
    t.string "title_fr"
    t.text "body_en"
    t.text "body_fr"
    t.integer "order"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "friendly_id_slugs", id: :serial, force: :cascade do |t|
    t.string "slug", null: false
    t.integer "sluggable_id", null: false
    t.string "sluggable_type", limit: 50
    t.string "scope"
    t.datetime "created_at", precision: nil
    t.index ["slug", "sluggable_type", "scope"], name: "index_friendly_id_slugs_on_slug_and_sluggable_type_and_scope", unique: true
    t.index ["slug", "sluggable_type"], name: "index_friendly_id_slugs_on_slug_and_sluggable_type"
    t.index ["sluggable_id"], name: "index_friendly_id_slugs_on_sluggable_id"
    t.index ["sluggable_type"], name: "index_friendly_id_slugs_on_sluggable_type"
  end

  create_table "job_options", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.boolean "need_files", default: false, null: false
    t.decimal "fee", precision: 10, scale: 2, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "job_options_types", id: false, force: :cascade do |t|
    t.bigint "job_type_id", null: false
    t.bigint "job_option_id", null: false
    t.index ["job_option_id"], name: "index_job_options_types_on_job_option_id"
    t.index ["job_type_id"], name: "index_job_options_types_on_job_type_id"
  end

  create_table "job_order_messages", force: :cascade do |t|
    t.text "name"
    t.text "message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "job_order_options", force: :cascade do |t|
    t.bigint "job_order_id", null: false
    t.bigint "job_option_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["job_option_id"], name: "index_job_order_options_on_job_option_id"
    t.index ["job_order_id"], name: "index_job_order_options_on_job_order_id"
  end

  create_table "job_order_quote_options", force: :cascade do |t|
    t.bigint "job_option_id", null: false
    t.integer "amount", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "job_order_quote_id"
    t.index ["job_option_id"], name: "index_job_order_quote_options_on_job_option_id"
    t.index ["job_order_quote_id"], name: "index_job_order_quote_options_on_job_order_quote_id"
  end

  create_table "job_order_quote_services", force: :cascade do |t|
    t.bigint "job_service_id", null: false
    t.decimal "quantity", precision: 10, scale: 2, null: false
    t.decimal "per_unit", precision: 10, scale: 2, null: false
    t.bigint "job_order_quote_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["job_order_quote_id"], name: "index_job_order_quote_services_on_job_order_quote_id"
    t.index ["job_service_id"], name: "index_job_order_quote_services_on_job_service_id"
  end

  create_table "job_order_quote_type_extras", force: :cascade do |t|
    t.bigint "job_type_extra_id"
    t.bigint "job_order_quote_id"
    t.decimal "price", precision: 10, scale: 2
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["job_order_quote_id"], name: "index_job_order_quote_type_extras_on_job_order_quote_id"
    t.index ["job_type_extra_id"], name: "index_job_order_quote_type_extras_on_job_type_extra_id"
  end

  create_table "job_order_quotes", force: :cascade do |t|
    t.decimal "service_fee", precision: 10, scale: 2, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "stripe_transaction_id"
  end

  create_table "job_order_statuses", force: :cascade do |t|
    t.bigint "job_order_id"
    t.bigint "job_status_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["job_order_id"], name: "index_job_order_statuses_on_job_order_id"
    t.index ["job_status_id"], name: "index_job_order_statuses_on_job_status_id"
    t.index ["user_id"], name: "index_job_order_statuses_on_user_id"
  end

  create_table "job_orders", force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "job_type_id"
    t.bigint "job_order_quote_id"
    t.text "staff_comments"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "job_service_group_id"
    t.text "comments"
    t.text "user_comments"
    t.boolean "is_deleted", default: false
    t.string "shopify_draft_order_id"
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

  create_table "job_service_groups", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.boolean "multiple", default: false
    t.integer "text_field", default: 0
    t.bigint "job_type_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["job_type_id"], name: "index_job_service_groups_on_job_type_id"
  end

  create_table "job_services", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.string "unit"
    t.boolean "required", default: false, null: false
    t.decimal "internal_price", precision: 10, scale: 2
    t.decimal "external_price", precision: 10, scale: 2
    t.bigint "job_service_group_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "job_order_id"
    t.boolean "user_created", default: false
    t.index ["job_order_id"], name: "index_job_services_on_job_order_id"
    t.index ["job_service_group_id"], name: "index_job_services_on_job_service_group_id"
  end

  create_table "job_statuses", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "name_fr"
    t.string "description_fr"
  end

  create_table "job_type_extras", force: :cascade do |t|
    t.bigint "job_type_id"
    t.string "name"
    t.decimal "price", precision: 10, scale: 2
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "description"
    t.index ["job_type_id"], name: "index_job_type_extras_on_job_type_id"
  end

  create_table "job_types", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.text "comments"
    t.boolean "multiple_files", default: false, null: false
    t.string "file_label", default: "File"
    t.text "file_description"
    t.decimal "service_fee", precision: 10, scale: 2
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "key_certifications", force: :cascade do |t|
    t.bigint "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_key_certifications_on_user_id"
  end

  create_table "key_requests", force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "supervisor_id"
    t.bigint "space_id"
    t.string "student_number"
    t.string "phone_number"
    t.string "emergency_contact"
    t.string "emergency_contact_relation"
    t.string "emergency_contact_phone_number"
    t.integer "user_status"
    t.integer "status"
    t.string "question_1"
    t.string "question_2"
    t.string "question_3"
    t.string "question_4"
    t.string "question_5"
    t.string "question_6"
    t.string "question_7"
    t.string "question_8"
    t.string "question_9"
    t.string "question_10"
    t.string "question_11"
    t.string "question_12"
    t.string "question_13"
    t.string "question_14"
    t.boolean "read_lab_rules", default: false, null: false
    t.boolean "read_policies", default: false, null: false
    t.boolean "read_agreement", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["space_id"], name: "index_key_requests_on_space_id"
    t.index ["supervisor_id"], name: "index_key_requests_on_supervisor_id"
    t.index ["user_id"], name: "index_key_requests_on_user_id"
  end

  create_table "key_transactions", force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "key_id"
    t.date "return_date"
    t.date "deposit_return_date"
    t.decimal "deposit_amount", precision: 5, scale: 2
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key_id"], name: "index_key_transactions_on_key_id"
    t.index ["user_id"], name: "index_key_transactions_on_user_id"
  end

  create_table "keys", force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "supervisor_id"
    t.bigint "space_id"
    t.string "number"
    t.string "custom_keycode"
    t.integer "status", default: 0
    t.integer "key_type", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "additional_info", default: ""
    t.index ["space_id"], name: "index_keys_on_space_id"
    t.index ["supervisor_id"], name: "index_keys_on_supervisor_id"
    t.index ["user_id"], name: "index_keys_on_user_id"
  end

  create_table "lab_sessions", id: :serial, force: :cascade do |t|
    t.integer "user_id"
    t.datetime "sign_in_time", precision: nil
    t.datetime "sign_out_time", precision: nil
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "mac_address"
    t.integer "space_id"
    t.index ["space_id"], name: "index_lab_sessions_on_space_id"
    t.index ["user_id"], name: "index_lab_sessions_on_user_id"
  end

  create_table "learning_module_tracks", force: :cascade do |t|
    t.string "status", default: "In progress"
    t.bigint "learning_module_id"
    t.bigint "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["learning_module_id"], name: "index_learning_module_tracks_on_learning_module_id"
    t.index ["user_id"], name: "index_learning_module_tracks_on_user_id"
  end

  create_table "learning_modules", force: :cascade do |t|
    t.integer "training_id"
    t.string "title"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "level", default: "Beginner"
    t.integer "order"
  end

  create_table "likes", id: :serial, force: :cascade do |t|
    t.integer "user_id"
    t.integer "repository_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["repository_id"], name: "index_likes_on_repository_id"
    t.index ["user_id"], name: "index_likes_on_user_id"
  end

  create_table "locker_rentals", force: :cascade do |t|
    t.bigint "locker_type_id"
    t.bigint "rented_by_id"
    t.string "locker_specifier"
    t.string "state"
    t.string "notes"
    t.datetime "owned_until"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "shopify_draft_order_id"
    t.index ["locker_type_id"], name: "index_locker_rentals_on_locker_type_id"
    t.index ["rented_by_id"], name: "index_locker_rentals_on_rented_by_id"
  end

  create_table "locker_types", force: :cascade do |t|
    t.string "short_form"
    t.string "description"
    t.boolean "available", default: true
    t.string "available_for"
    t.integer "quantity", default: 0
    t.decimal "cost", default: "0.0"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "makerstore_links", force: :cascade do |t|
    t.integer "order", default: 0
    t.string "title"
    t.string "url"
    t.boolean "shown", default: true
  end

  create_table "opening_hours", force: :cascade do |t|
    t.bigint "contact_info_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "target_en"
    t.string "target_fr"
    t.time "sunday_opening"
    t.time "sunday_closing"
    t.integer "sunday_closed_all_day", default: 0
    t.time "monday_opening"
    t.time "monday_closing"
    t.integer "monday_closed_all_day", default: 0
    t.time "tuesday_opening"
    t.time "tuesday_closing"
    t.integer "tuesday_closed_all_day", default: 0
    t.time "wednesday_opening"
    t.time "wednesday_closing"
    t.integer "wednesday_closed_all_day", default: 0
    t.time "thursday_opening"
    t.time "thursday_closing"
    t.integer "thursday_closed_all_day", default: 0
    t.time "friday_opening"
    t.time "friday_closing"
    t.integer "friday_closed_all_day", default: 0
    t.time "saturday_opening"
    t.time "saturday_closing"
    t.integer "saturday_closed_all_day", default: 0
    t.integer "closed_all_week", default: 0
    t.text "notes_en"
    t.text "notes_fr"
    t.index ["contact_info_id"], name: "index_opening_hours_on_contact_info_id"
  end

  create_table "order_items", id: :serial, force: :cascade do |t|
    t.integer "proficient_project_id"
    t.integer "order_id"
    t.decimal "unit_price", precision: 12, scale: 3
    t.decimal "total_price", precision: 12, scale: 3
    t.integer "quantity"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "status", default: "In progress"
    t.text "user_comments", default: ""
    t.text "admin_comments", default: ""
  end

  create_table "order_statuses", id: :serial, force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "orders", id: :serial, force: :cascade do |t|
    t.integer "order_status_id"
    t.decimal "subtotal", precision: 12, scale: 3
    t.decimal "total", precision: 12, scale: 3
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "user_id"
  end

  create_table "photos", id: :serial, force: :cascade do |t|
    t.integer "repository_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "image_file_name"
    t.string "image_content_type"
    t.integer "image_file_size"
    t.datetime "image_updated_at", precision: nil
    t.integer "height"
    t.integer "width"
    t.integer "proficient_project_id"
    t.integer "learning_module_id"
    t.integer "project_proposal_id"
    t.integer "volunteer_task_id"
    t.index ["repository_id"], name: "index_photos_on_repository_id"
  end

  create_table "pi_readers", id: :serial, force: :cascade do |t|
    t.string "pi_mac_address"
    t.string "pi_location"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "space_id"
    t.index ["space_id"], name: "index_pi_readers_on_space_id"
  end

  create_table "popular_hours", force: :cascade do |t|
    t.bigint "space_id"
    t.float "mean", default: 0.0
    t.integer "hour"
    t.integer "day"
    t.integer "count", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.float "previous_mean", default: 0.0
    t.index ["space_id"], name: "index_popular_hours_on_space_id"
  end

  create_table "price_rules", id: :serial, force: :cascade do |t|
    t.string "shopify_price_rule_id"
    t.string "title"
    t.integer "value"
    t.integer "cc"
    t.integer "usage_limit"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.datetime "expired_at", precision: nil
  end

  create_table "print_orders", id: :serial, force: :cascade do |t|
    t.integer "user_id"
    t.boolean "approved"
    t.boolean "printed"
    t.text "comments"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "file_file_name"
    t.string "file_content_type"
    t.integer "file_file_size"
    t.datetime "file_updated_at", precision: nil
    t.float "quote"
    t.integer "staff_id"
    t.boolean "user_approval"
    t.text "staff_comments"
    t.boolean "expedited"
    t.integer "order_type", default: 0
    t.datetime "timestamp_approved", precision: nil
    t.string "final_file_file_name"
    t.string "final_file_content_type"
    t.integer "final_file_file_size"
    t.datetime "final_file_updated_at", precision: nil
    t.float "grams"
    t.float "service_charge"
    t.float "price_per_hour"
    t.float "price_per_gram"
    t.float "material_cost"
    t.boolean "sst"
    t.text "material"
    t.float "hours"
    t.string "comments_for_staff"
    t.float "grams_fiberglass", default: 0.0
    t.float "price_per_gram_fiberglass", default: 0.0
    t.float "grams_carbonfiber", default: 0.0
    t.float "price_per_gram_carbonfiber", default: 0.0
    t.boolean "payed"
    t.boolean "picked_up"
    t.boolean "clean_part"
    t.datetime "timestamp_printed", precision: nil
    t.string "comments_box"
  end

  create_table "printer_issues", force: :cascade do |t|
    t.bigint "printer_id", null: false
    t.string "summary", null: false
    t.string "description"
    t.bigint "reporter_id", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["printer_id"], name: "index_printer_issues_on_printer_id"
    t.index ["reporter_id"], name: "index_printer_issues_on_reporter_id"
  end

  create_table "printer_sessions", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "user_id"
    t.integer "printer_id"
    t.boolean "in_use", default: false
  end

  create_table "printer_types", force: :cascade do |t|
    t.string "name"
    t.string "short_form", default: ""
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "available", default: true
  end

  create_table "printers", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "number"
    t.bigint "printer_type_id"
    t.boolean "maintenance", default: false
    t.index ["printer_type_id"], name: "index_printers_on_printer_type_id"
  end

  create_table "proficient_project_sessions", force: :cascade do |t|
    t.bigint "certification_id"
    t.bigint "proficient_project_id"
    t.bigint "user_id"
    t.string "level"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["certification_id"], name: "index_proficient_project_sessions_on_certification_id"
    t.index ["proficient_project_id"], name: "index_proficient_project_sessions_on_proficient_project_id"
    t.index ["user_id"], name: "index_proficient_project_sessions_on_user_id"
  end

  create_table "proficient_projects", id: :serial, force: :cascade do |t|
    t.integer "training_id"
    t.string "title"
    t.text "description"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "level", default: "Beginner"
    t.integer "cc", default: 0
    t.boolean "has_project_kit"
    t.bigint "drop_off_location_id"
    t.boolean "is_virtual", default: false
    t.index ["drop_off_location_id"], name: "index_proficient_projects_on_drop_off_location_id"
  end

  create_table "proficient_projects_users", id: false, force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "proficient_project_id", null: false
  end

  create_table "programs", id: :serial, force: :cascade do |t|
    t.integer "user_id"
    t.string "program_type"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.boolean "active", default: true
  end

  create_table "project_joins", id: :serial, force: :cascade do |t|
    t.integer "user_id"
    t.integer "project_proposal_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "project_kits", force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "proficient_project_id"
    t.string "name"
    t.boolean "delivered", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "learning_module_id"
    t.index ["learning_module_id"], name: "index_project_kits_on_learning_module_id"
    t.index ["proficient_project_id"], name: "index_project_kits_on_proficient_project_id"
    t.index ["user_id"], name: "index_project_kits_on_user_id"
  end

  create_table "project_proposals", id: :serial, force: :cascade do |t|
    t.integer "user_id"
    t.integer "admin_id"
    t.integer "approved"
    t.string "title"
    t.text "description"
    t.string "youtube_link"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "username"
    t.string "email"
    t.string "client"
    t.string "area", default: [], array: true
    t.string "client_type"
    t.string "client_interest"
    t.string "client_background"
    t.string "supervisor_background"
    t.text "equipments", default: "Not informed / Pas informé"
    t.string "project_type"
    t.integer "project_cost"
    t.string "past_experiences"
    t.string "slug"
    t.bigint "linked_project_proposal_id"
    t.integer "prototype_cost"
    t.index ["linked_project_proposal_id"], name: "index_project_proposals_on_linked_project_proposal_id"
  end

  create_table "project_requirements", id: :serial, force: :cascade do |t|
    t.integer "proficient_project_id"
    t.integer "required_project_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "questions", id: :serial, force: :cascade do |t|
    t.integer "user_id"
    t.text "description"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "image_file_name"
    t.string "image_content_type"
    t.integer "image_file_size"
    t.datetime "image_updated_at", precision: nil
    t.integer "training_id"
    t.string "level", default: "Beginner"
  end

  create_table "questions_trainings", id: false, force: :cascade do |t|
    t.bigint "question_id", null: false
    t.bigint "training_id", null: false
  end

  create_table "quick_access_links", force: :cascade do |t|
    t.string "name"
    t.string "path"
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_quick_access_links_on_user_id"
  end

  create_table "recurring_bookings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "repo_files", id: :serial, force: :cascade do |t|
    t.integer "repository_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "file_file_name"
    t.string "file_content_type"
    t.integer "file_file_size"
    t.datetime "file_updated_at", precision: nil
    t.integer "proficient_project_id"
    t.integer "learning_module_id"
    t.integer "project_proposal_id"
    t.index ["repository_id"], name: "index_repo_files_on_repository_id"
  end

  create_table "repositories", id: :serial, force: :cascade do |t|
    t.integer "user_id"
    t.string "title"
    t.string "description"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "category"
    t.string "license"
    t.string "github"
    t.string "github_url"
    t.integer "like", default: 0
    t.string "user_username"
    t.integer "make_id"
    t.integer "make", default: 0
    t.string "slug"
    t.string "share_type"
    t.string "password"
    t.boolean "featured", default: false
    t.string "youtube_link"
    t.integer "project_proposal_id"
    t.boolean "deleted"
    t.index ["user_id"], name: "index_repositories_on_user_id"
  end

  create_table "repositories_users", id: false, force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "repository_id", null: false
  end

  create_table "require_trainings", id: :serial, force: :cascade do |t|
    t.integer "volunteer_task_id"
    t.integer "training_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "rfids", id: :serial, force: :cascade do |t|
    t.integer "user_id"
    t.string "card_number"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "mac_address"
    t.index ["user_id"], name: "index_rfids_on_user_id"
  end

  create_table "shadowing_hours", force: :cascade do |t|
    t.bigint "user_id"
    t.string "event_id"
    t.datetime "start_time", precision: nil
    t.datetime "end_time", precision: nil
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "space_id"
    t.index ["space_id"], name: "index_shadowing_hours_on_space_id"
    t.index ["user_id"], name: "index_shadowing_hours_on_user_id"
  end

  create_table "shifts", force: :cascade do |t|
    t.text "reason"
    t.bigint "space_id"
    t.datetime "start_datetime", precision: nil
    t.datetime "end_datetime", precision: nil
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "google_event_id"
    t.boolean "pending", default: true
    t.bigint "training_id"
    t.string "language"
    t.string "course"
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
    t.text "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "space_manager_joins", force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "space_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["space_id"], name: "index_space_manager_joins_on_space_id"
    t.index ["user_id"], name: "index_space_manager_joins_on_user_id"
  end

  create_table "space_staff_hours", force: :cascade do |t|
    t.time "start_time"
    t.time "end_time"
    t.integer "day"
    t.bigint "space_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "language"
    t.bigint "training_level_id"
    t.bigint "course_name_id"
    t.index ["course_name_id"], name: "index_space_staff_hours_on_course_name_id"
    t.index ["space_id"], name: "index_space_staff_hours_on_space_id"
    t.index ["training_level_id"], name: "index_space_staff_hours_on_training_level_id"
  end

  create_table "spaces", id: :serial, force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "max_capacity"
    t.integer "destroy_admin_id"
    t.string "keycode", default: ""
  end

  create_table "spaces_trainings", id: false, force: :cascade do |t|
    t.integer "space_id", null: false
    t.integer "training_id", null: false
  end

  create_table "staff_availabilities", force: :cascade do |t|
    t.bigint "user_id"
    t.string "day"
    t.time "start_time"
    t.time "end_time"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "time_period_id"
    t.boolean "recurring", default: true
    t.datetime "start_datetime"
    t.datetime "end_datetime"
    t.index ["time_period_id"], name: "index_staff_availabilities_on_time_period_id"
    t.index ["user_id"], name: "index_staff_availabilities_on_user_id"
  end

  create_table "staff_availability_exceptions", force: :cascade do |t|
    t.bigint "staff_availability_id"
    t.datetime "start_at"
    t.integer "covers", default: 0
    t.index ["staff_availability_id"], name: "index_staff_availability_exceptions_on_staff_availability_id"
  end

  create_table "staff_needed_calendars", force: :cascade do |t|
    t.string "calendar_url", null: false
    t.string "color"
    t.bigint "space_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["space_id"], name: "index_staff_needed_calendars_on_space_id"
  end

  create_table "staff_spaces", force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "space_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "color"
    t.index ["space_id"], name: "index_staff_spaces_on_space_id"
    t.index ["user_id"], name: "index_staff_spaces_on_user_id"
  end

  create_table "sub_space_booking_statuses", force: :cascade do |t|
    t.bigint "sub_space_booking_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "booking_status_id"
    t.index ["booking_status_id"], name: "index_sub_space_booking_statuses_on_booking_status_id"
    t.index ["sub_space_booking_id"], name: "index_sub_space_booking_statuses_on_sub_space_booking_id"
  end

  create_table "sub_space_bookings", force: :cascade do |t|
    t.string "name"
    t.string "description"
    t.datetime "start_time", precision: nil
    t.datetime "end_time", precision: nil
    t.bigint "user_id"
    t.bigint "sub_space_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "sub_space_booking_status_id"
    t.boolean "public", default: false
    t.boolean "blocking", default: false
    t.bigint "approved_by_id"
    t.datetime "approved_at"
    t.bigint "recurring_booking_id"
    t.index ["approved_by_id"], name: "index_sub_space_bookings_on_approved_by_id"
    t.index ["recurring_booking_id"], name: "index_sub_space_bookings_on_recurring_booking_id"
    t.index ["sub_space_booking_status_id"], name: "index_sub_space_bookings_on_sub_space_booking_status_id"
    t.index ["sub_space_id"], name: "index_sub_space_bookings_on_sub_space_id"
    t.index ["user_id"], name: "index_sub_space_bookings_on_user_id"
  end

  create_table "sub_spaces", force: :cascade do |t|
    t.string "name"
    t.bigint "space_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "approval_required", default: false
    t.integer "maximum_booking_duration"
    t.integer "maximum_booking_hours_per_week"
    t.boolean "default_public", default: false
    t.integer "max_automatic_approval_hour"
    t.index ["space_id"], name: "index_sub_spaces_on_space_id"
  end

  create_table "team_memberships", force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "team_id"
    t.integer "role", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["team_id"], name: "index_team_memberships_on_team_id"
    t.index ["user_id"], name: "index_team_memberships_on_user_id"
  end

  create_table "teams", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "time_periods", force: :cascade do |t|
    t.string "name"
    t.date "start_date"
    t.date "end_date"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "training_levels", force: :cascade do |t|
    t.string "name"
    t.bigint "space_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["space_id"], name: "index_training_levels_on_space_id"
  end

  create_table "training_requirements", force: :cascade do |t|
    t.bigint "training_id"
    t.bigint "proficient_project_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["proficient_project_id"], name: "index_training_requirements_on_proficient_project_id"
    t.index ["training_id"], name: "index_training_requirements_on_training_id"
  end

  create_table "training_sessions", id: :serial, force: :cascade do |t|
    t.integer "training_id"
    t.integer "user_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "course"
    t.integer "space_id"
    t.string "level", default: "Beginner"
    t.integer "course_name_id"
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
    t.string "name_en"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "space_id"
    t.bigint "skill_id"
    t.string "description_en"
    t.string "list_of_skills_en"
    t.string "name_fr"
    t.boolean "has_badge", default: true
    t.string "description_fr"
    t.string "list_of_skills_fr"
    t.index ["skill_id"], name: "index_trainings_on_skill_id"
    t.index ["space_id"], name: "index_trainings_on_space_id"
  end

  create_table "uni_programs", id: false, force: :cascade do |t|
    t.string "program", null: false
    t.string "faculty", null: false
    t.string "level", null: false
    t.string "department", null: false
    t.index ["program"], name: "index_uni_programs_on_program"
  end

  create_table "upvotes", id: :serial, force: :cascade do |t|
    t.integer "user_id"
    t.integer "comment_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.boolean "downvote"
    t.index ["comment_id"], name: "index_upvotes_on_comment_id"
    t.index ["user_id"], name: "index_upvotes_on_user_id"
  end

  create_table "user_booking_approvals", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.date "date"
    t.string "comments"
    t.bigint "staff_id"
    t.boolean "approved"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "identity"
    t.index ["staff_id"], name: "index_user_booking_approvals_on_staff_id"
    t.index ["user_id"], name: "index_user_booking_approvals_on_user_id"
  end

  create_table "users", id: :serial, force: :cascade do |t|
    t.string "username"
    t.string "password"
    t.string "url"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.text "description"
    t.string "email"
    t.string "avatar_file_name"
    t.string "avatar_content_type"
    t.integer "avatar_file_size"
    t.datetime "avatar_updated_at", precision: nil
    t.string "access_token"
    t.string "name"
    t.string "gender"
    t.string "faculty"
    t.string "use"
    t.integer "reputation", default: 0
    t.string "role", default: "regular_user"
    t.boolean "terms_and_conditions"
    t.string "program"
    t.string "how_heard_about_us"
    t.string "identity"
    t.string "year_of_study"
    t.boolean "read_and_accepted_waiver_form", default: false
    t.boolean "active", default: true
    t.datetime "last_seen_at", precision: nil
    t.integer "wallet", default: 0
    t.boolean "flagged"
    t.string "flag_message", default: ""
    t.boolean "confirmed", default: false
    t.bigint "space_id"
    t.datetime "last_signed_in_time", precision: nil
    t.boolean "deleted"
    t.boolean "booking_approval", default: false
    t.boolean "locked", default: false
    t.datetime "locked_until", precision: nil
    t.integer "auth_attempts", default: 0
    t.string "student_id"
    t.index ["space_id"], name: "index_users_on_space_id"
  end

  create_table "videos", id: :serial, force: :cascade do |t|
    t.integer "proficient_project_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.boolean "processed", default: false, null: false
    t.bigint "learning_module_id"
    t.index ["learning_module_id"], name: "index_videos_on_learning_module_id"
    t.index ["proficient_project_id"], name: "index_videos_on_proficient_project_id"
  end

  create_table "volunteer_hours", id: :serial, force: :cascade do |t|
    t.integer "volunteer_task_id", null: false
    t.integer "user_id", null: false
    t.datetime "date_of_task", precision: nil
    t.decimal "total_time", precision: 9, scale: 2, default: "0.0"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.boolean "approval"
  end

  create_table "volunteer_task_joins", id: :serial, force: :cascade do |t|
    t.integer "user_id"
    t.integer "volunteer_task_id"
    t.string "user_type", default: "Volunteer"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.boolean "active", default: true
  end

  create_table "volunteer_task_requests", id: :serial, force: :cascade do |t|
    t.integer "user_id"
    t.integer "volunteer_task_id"
    t.boolean "approval"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "volunteer_tasks", id: :serial, force: :cascade do |t|
    t.string "title", default: ""
    t.text "description", default: ""
    t.integer "user_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "status", default: "open"
    t.integer "space_id"
    t.integer "joins", default: 1
    t.string "category", default: "Other"
    t.integer "cc", default: 0
    t.decimal "hours", precision: 5, scale: 2, default: "0.0"
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
  add_foreign_key "comments", "repositories"
  add_foreign_key "comments", "users"
  add_foreign_key "contact_infos", "spaces"
  add_foreign_key "coupon_codes", "users"
  add_foreign_key "discount_codes", "price_rules"
  add_foreign_key "discount_codes", "users"
  add_foreign_key "equipment", "repositories"
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
  add_foreign_key "job_service_groups", "job_types"
  add_foreign_key "job_services", "job_orders"
  add_foreign_key "job_services", "job_service_groups"
  add_foreign_key "job_type_extras", "job_types"
  add_foreign_key "lab_sessions", "spaces"
  add_foreign_key "learning_module_tracks", "learning_modules"
  add_foreign_key "learning_module_tracks", "users"
  add_foreign_key "likes", "repositories"
  add_foreign_key "likes", "users"
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
  add_foreign_key "space_staff_hours", "course_names"
  add_foreign_key "space_staff_hours", "spaces"
  add_foreign_key "space_staff_hours", "training_levels"
  add_foreign_key "staff_availabilities", "time_periods"
  add_foreign_key "staff_availabilities", "users"
  add_foreign_key "staff_needed_calendars", "spaces"
  add_foreign_key "staff_spaces", "spaces"
  add_foreign_key "staff_spaces", "users"
  add_foreign_key "sub_space_booking_statuses", "booking_statuses"
  add_foreign_key "sub_space_booking_statuses", "sub_space_bookings", on_delete: :cascade
  add_foreign_key "sub_space_bookings", "recurring_bookings"
  add_foreign_key "sub_space_bookings", "sub_space_booking_statuses"
  add_foreign_key "sub_space_bookings", "sub_spaces", on_delete: :cascade
  add_foreign_key "sub_space_bookings", "users"
  add_foreign_key "sub_space_bookings", "users", column: "approved_by_id"
  add_foreign_key "sub_spaces", "spaces"
  add_foreign_key "training_levels", "spaces"
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
end
