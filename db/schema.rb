# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `rails
# db:schema:load`. When creating a new database, `rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 2020_08_24_141813) do

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
    t.bigint "byte_size", null: false
    t.string "checksum", null: false
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "announcements", id: :serial, force: :cascade do |t|
    t.text "description"
    t.string "public_goal"
    t.integer "user_id"
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "answers", id: :serial, force: :cascade do |t|
    t.integer "question_id"
    t.text "description"
    t.boolean "correct", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "area_options", id: :serial, force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "badge_requirements", id: :serial, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "badge_template_id"
    t.integer "proficient_project_id"
    t.index ["badge_template_id"], name: "index_badge_requirements_on_badge_template_id"
    t.index ["proficient_project_id"], name: "index_badge_requirements_on_proficient_project_id"
  end

  create_table "badge_templates", id: :serial, force: :cascade do |t|
    t.text "acclaim_template_id"
    t.text "badge_description"
    t.text "badge_name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "image_url"
  end

  create_table "badges", id: :serial, force: :cascade do |t|
    t.string "issued_to"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "acclaim_badge_id"
    t.integer "user_id"
    t.string "badge_url"
    t.integer "badge_template_id"
    t.index ["badge_template_id"], name: "index_badges_on_badge_template_id"
  end

  create_table "categories", id: :serial, force: :cascade do |t|
    t.integer "repository_id"
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "category_option_id"
    t.integer "project_proposal_id"
    t.index ["category_option_id"], name: "index_categories_on_category_option_id"
    t.index ["repository_id"], name: "index_categories_on_repository_id"
  end

  create_table "category_options", id: :serial, force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "cc_moneys", id: :serial, force: :cascade do |t|
    t.integer "user_id"
    t.integer "volunteer_task_id"
    t.integer "cc"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "training_session_id"
    t.index ["user_id"], name: "index_certifications_on_user_id"
  end

  create_table "comments", id: :serial, force: :cascade do |t|
    t.integer "user_id"
    t.integer "repository_id"
    t.text "content"
    t.integer "upvote", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "username"
    t.index ["repository_id"], name: "index_comments_on_repository_id"
    t.index ["user_id"], name: "index_comments_on_user_id"
  end

  create_table "courses", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
  end

  create_table "discount_codes", id: :serial, force: :cascade do |t|
    t.integer "price_rule_id"
    t.integer "user_id"
    t.string "shopify_discount_code_id"
    t.string "code"
    t.integer "usage_count"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["price_rule_id"], name: "index_discount_codes_on_price_rule_id"
    t.index ["user_id"], name: "index_discount_codes_on_user_id"
  end

  create_table "equipment", id: :serial, force: :cascade do |t|
    t.integer "repository_id"
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["repository_id"], name: "index_equipment_on_repository_id"
  end

  create_table "equipment_options", id: :serial, force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "exam_questions", id: :serial, force: :cascade do |t|
    t.integer "exam_id"
    t.integer "question_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "exam_responses", id: :serial, force: :cascade do |t|
    t.integer "exam_question_id"
    t.integer "answer_id"
    t.boolean "correct"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "exams", id: :serial, force: :cascade do |t|
    t.integer "user_id"
    t.string "category"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "status", default: "not started"
    t.integer "score"
    t.integer "training_session_id"
    t.datetime "expired_at"
  end

  create_table "lab_sessions", id: :serial, force: :cascade do |t|
    t.integer "user_id"
    t.datetime "sign_in_time"
    t.datetime "sign_out_time"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "mac_address"
    t.integer "space_id"
    t.index ["space_id"], name: "index_lab_sessions_on_space_id"
    t.index ["user_id"], name: "index_lab_sessions_on_user_id"
  end

  create_table "likes", id: :serial, force: :cascade do |t|
    t.integer "user_id"
    t.integer "repository_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["repository_id"], name: "index_likes_on_repository_id"
    t.index ["user_id"], name: "index_likes_on_user_id"
  end

  create_table "order_items", id: :serial, force: :cascade do |t|
    t.integer "proficient_project_id"
    t.integer "order_id"
    t.decimal "unit_price", precision: 12, scale: 3
    t.decimal "total_price", precision: 12, scale: 3
    t.integer "quantity"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "status", default: "In progress"
  end

  create_table "order_statuses", id: :serial, force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "orders", id: :serial, force: :cascade do |t|
    t.integer "order_status_id"
    t.decimal "subtotal", precision: 12, scale: 3
    t.decimal "total", precision: 12, scale: 3
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
  end

  create_table "photos", id: :serial, force: :cascade do |t|
    t.integer "repository_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "image_file_name"
    t.string "image_content_type"
    t.integer "image_file_size"
    t.datetime "image_updated_at"
    t.integer "height"
    t.integer "width"
    t.integer "proficient_project_id"
    t.index ["repository_id"], name: "index_photos_on_repository_id"
  end

  create_table "pi_readers", id: :serial, force: :cascade do |t|
    t.string "pi_mac_address"
    t.string "pi_location"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "space_id"
    t.index ["space_id"], name: "index_pi_readers_on_space_id"
  end

  create_table "popular_hours", force: :cascade do |t|
    t.integer "mean"
    t.integer "space_id"
    t.integer "hour"
    t.integer "day"
    t.integer "count"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
  end

  create_table "price_rules", id: :serial, force: :cascade do |t|
    t.string "shopify_price_rule_id"
    t.string "title"
    t.integer "value"
    t.integer "cc"
    t.integer "usage_limit"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "expired_at"
  end

  create_table "print_orders", id: :serial, force: :cascade do |t|
    t.integer "user_id"
    t.boolean "approved"
    t.boolean "printed"
    t.text "comments"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "file_file_name"
    t.string "file_content_type"
    t.integer "file_file_size"
    t.datetime "file_updated_at"
    t.float "quote"
    t.integer "staff_id"
    t.boolean "user_approval"
    t.text "staff_comments"
    t.boolean "expedited"
    t.integer "order_type", default: 0
    t.text "email"
    t.text "name"
    t.datetime "timestamp_approved"
    t.string "final_file_file_name"
    t.string "final_file_content_type"
    t.integer "final_file_file_size"
    t.datetime "final_file_updated_at"
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
  end

  create_table "printer_sessions", id: :serial, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.integer "printer_id"
  end

  create_table "printers", id: :serial, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "model"
    t.string "number"
    t.string "status", default: "true"
    t.string "availability", default: "true"
    t.string "color", default: "FF0000"
    t.string "rfid"
  end

  create_table "proficient_projects", id: :serial, force: :cascade do |t|
    t.integer "training_id"
    t.string "title"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "level", default: "Beginner"
    t.integer "cc", default: 0
    t.boolean "proficient", default: true
    t.integer "badge_template_id"
    t.boolean "has_project_kit"
    t.index ["badge_template_id"], name: "index_proficient_projects_on_badge_template_id"
  end

  create_table "proficient_projects_users", id: false, force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "proficient_project_id", null: false
  end

  create_table "programs", id: :serial, force: :cascade do |t|
    t.integer "user_id"
    t.string "program_type"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "project_joins", id: :serial, force: :cascade do |t|
    t.integer "user_id"
    t.integer "project_proposal_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "project_kits", force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "proficient_project_id"
    t.string "name"
    t.boolean "delivered", default: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
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
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "username"
    t.string "email"
    t.string "client"
    t.string "area", default: [], array: true
    t.string "client_type"
    t.string "client_interest"
    t.string "client_background"
    t.string "supervisor_background"
    t.text "equipments", default: "Not informed."
  end

  create_table "project_requirements", id: :serial, force: :cascade do |t|
    t.integer "proficient_project_id"
    t.integer "required_project_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "questions", id: :serial, force: :cascade do |t|
    t.integer "user_id"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "image_file_name"
    t.string "image_content_type"
    t.integer "image_file_size"
    t.datetime "image_updated_at"
    t.integer "training_id"
  end

  create_table "questions_trainings", id: false, force: :cascade do |t|
    t.bigint "question_id", null: false
    t.bigint "training_id", null: false
  end

  create_table "repo_files", id: :serial, force: :cascade do |t|
    t.integer "repository_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "file_file_name"
    t.string "file_content_type"
    t.integer "file_file_size"
    t.datetime "file_updated_at"
    t.integer "proficient_project_id"
    t.index ["repository_id"], name: "index_repo_files_on_repository_id"
  end

  create_table "repositories", id: :serial, force: :cascade do |t|
    t.integer "user_id"
    t.string "title"
    t.string "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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
    t.index ["user_id"], name: "index_repositories_on_user_id"
  end

  create_table "repositories_users", id: false, force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "repository_id", null: false
  end

  create_table "require_trainings", id: :serial, force: :cascade do |t|
    t.integer "volunteer_task_id"
    t.integer "training_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "rfids", id: :serial, force: :cascade do |t|
    t.integer "user_id"
    t.string "card_number"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "mac_address"
    t.index ["user_id"], name: "index_rfids_on_user_id"
  end

  create_table "sd_signins", id: :serial, force: :cascade do |t|
    t.integer "printer_id"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "skills", id: :serial, force: :cascade do |t|
    t.integer "user_id"
    t.string "printing", default: "No Experience"
    t.string "laser_cutting", default: "No Experience"
    t.string "virtual_reality", default: "No Experience"
    t.string "arduino", default: "No Experience"
    t.string "embroidery", default: "No Experience"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "active", default: true
    t.string "soldering", default: "No Experience"
  end

  create_table "spaces", id: :serial, force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "spaces_trainings", id: false, force: :cascade do |t|
    t.integer "space_id", null: false
    t.integer "training_id", null: false
  end

  create_table "training_sessions", id: :serial, force: :cascade do |t|
    t.integer "training_id"
    t.integer "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "course"
    t.integer "space_id"
    t.string "level", default: "Beginner"
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
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "space_id"
    t.index ["space_id"], name: "index_trainings_on_space_id"
  end

  create_table "upvotes", id: :serial, force: :cascade do |t|
    t.integer "user_id"
    t.integer "comment_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "downvote"
    t.index ["comment_id"], name: "index_upvotes_on_comment_id"
    t.index ["user_id"], name: "index_upvotes_on_user_id"
  end

  create_table "users", id: :serial, force: :cascade do |t|
    t.string "username"
    t.string "password"
    t.string "url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "description"
    t.string "email"
    t.string "avatar_file_name"
    t.string "avatar_content_type"
    t.integer "avatar_file_size"
    t.datetime "avatar_updated_at"
    t.string "access_token"
    t.string "name"
    t.string "gender"
    t.string "faculty"
    t.string "use"
    t.integer "reputation", default: 0
    t.string "role", default: "regular_user"
    t.boolean "terms_and_conditions"
    t.string "program"
    t.integer "student_id"
    t.string "how_heard_about_us"
    t.string "identity"
    t.string "year_of_study"
    t.boolean "read_and_accepted_waiver_form", default: false
    t.boolean "active", default: true
    t.datetime "last_seen_at"
    t.integer "wallet", default: 0
    t.boolean "flagged"
    t.string "flag_message"
    t.boolean "confirmed", default: false
  end

  create_table "videos", id: :serial, force: :cascade do |t|
    t.integer "proficient_project_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "video_file_name"
    t.string "video_content_type"
    t.integer "video_file_size"
    t.datetime "video_updated_at"
    t.string "direct_upload_url", null: false
    t.boolean "processed", default: false, null: false
    t.index ["proficient_project_id"], name: "index_videos_on_proficient_project_id"
  end

  create_table "volunteer_hours", id: :serial, force: :cascade do |t|
    t.integer "volunteer_task_id", null: false
    t.integer "user_id", null: false
    t.datetime "date_of_task"
    t.decimal "total_time", precision: 9, scale: 2, default: "0.0"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "approval"
  end

  create_table "volunteer_requests", id: :serial, force: :cascade do |t|
    t.text "interests", default: ""
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.boolean "approval"
    t.integer "space_id"
    t.string "printing", default: "No Experience"
    t.string "laser_cutting", default: "No Experience"
    t.string "virtual_reality", default: "No Experience"
    t.string "arduino", default: "No Experience"
    t.string "embroidery", default: "No Experience"
    t.string "soldering", default: "No Experience"
  end

  create_table "volunteer_task_joins", id: :serial, force: :cascade do |t|
    t.integer "user_id"
    t.integer "volunteer_task_id"
    t.string "user_type", default: "Volunteer"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "active", default: true
  end

  create_table "volunteer_task_requests", id: :serial, force: :cascade do |t|
    t.integer "user_id"
    t.integer "volunteer_task_id"
    t.boolean "approval"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "volunteer_tasks", id: :serial, force: :cascade do |t|
    t.string "title", default: ""
    t.text "description", default: ""
    t.integer "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "status", default: "open"
    t.integer "space_id"
    t.integer "joins", default: 1
    t.string "category", default: "Other"
    t.integer "cc", default: 0
    t.decimal "hours", precision: 5, scale: 2, default: "0.0"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "badge_requirements", "badge_templates"
  add_foreign_key "badge_requirements", "proficient_projects"
  add_foreign_key "badges", "badge_templates"
  add_foreign_key "categories", "category_options"
  add_foreign_key "categories", "repositories"
  add_foreign_key "cc_moneys", "discount_codes"
  add_foreign_key "cc_moneys", "orders"
  add_foreign_key "cc_moneys", "proficient_projects"
  add_foreign_key "certifications", "users"
  add_foreign_key "comments", "repositories"
  add_foreign_key "comments", "users"
  add_foreign_key "discount_codes", "price_rules"
  add_foreign_key "discount_codes", "users"
  add_foreign_key "equipment", "repositories"
  add_foreign_key "lab_sessions", "spaces"
  add_foreign_key "likes", "repositories"
  add_foreign_key "likes", "users"
  add_foreign_key "order_items", "orders"
  add_foreign_key "order_items", "proficient_projects"
  add_foreign_key "orders", "order_statuses"
  add_foreign_key "photos", "repositories"
  add_foreign_key "pi_readers", "spaces"
  add_foreign_key "proficient_projects", "badge_templates"
  add_foreign_key "project_kits", "proficient_projects"
  add_foreign_key "project_kits", "users"
  add_foreign_key "repo_files", "repositories"
  add_foreign_key "repositories", "users"
  add_foreign_key "rfids", "users"
  add_foreign_key "training_sessions", "trainings"
  add_foreign_key "training_sessions", "users"
  add_foreign_key "trainings", "spaces"
  add_foreign_key "upvotes", "comments"
  add_foreign_key "upvotes", "users"
  add_foreign_key "videos", "proficient_projects"
end
