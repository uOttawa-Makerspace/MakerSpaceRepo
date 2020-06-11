# encoding: UTF-8
# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 20200224233026) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "announcements", force: :cascade do |t|
    t.text     "description"
    t.string   "public_goal"
    t.integer  "user_id"
    t.boolean  "active",      default: true
    t.datetime "created_at",                 null: false
    t.datetime "updated_at",                 null: false
  end

  create_table "answers", force: :cascade do |t|
    t.integer  "question_id"
    t.text     "description"
    t.boolean  "correct",     default: false
    t.datetime "created_at",                  null: false
    t.datetime "updated_at",                  null: false
  end

  create_table "area_options", force: :cascade do |t|
    t.string   "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "badge_requirements", force: :cascade do |t|
    t.datetime "created_at",            null: false
    t.datetime "updated_at",            null: false
    t.integer  "badge_template_id"
    t.integer  "proficient_project_id"
  end

  add_index "badge_requirements", ["badge_template_id"], name: "index_badge_requirements_on_badge_template_id", using: :btree
  add_index "badge_requirements", ["proficient_project_id"], name: "index_badge_requirements_on_proficient_project_id", using: :btree

  create_table "badge_templates", force: :cascade do |t|
    t.text     "acclaim_template_id"
    t.text     "badge_description"
    t.text     "badge_name"
    t.datetime "created_at",          null: false
    t.datetime "updated_at",          null: false
    t.string   "image_url"
  end

  create_table "badges", force: :cascade do |t|
    t.string   "issued_to"
    t.datetime "created_at",        null: false
    t.datetime "updated_at",        null: false
    t.string   "acclaim_badge_id"
    t.integer  "user_id"
    t.string   "badge_url"
    t.integer  "badge_template_id"
  end

  add_index "badges", ["badge_template_id"], name: "index_badges_on_badge_template_id", using: :btree

  create_table "categories", force: :cascade do |t|
    t.integer  "repository_id"
    t.string   "name"
    t.datetime "created_at",          null: false
    t.datetime "updated_at",          null: false
    t.integer  "category_option_id"
    t.integer  "project_proposal_id"
  end

  add_index "categories", ["category_option_id"], name: "index_categories_on_category_option_id", using: :btree
  add_index "categories", ["repository_id"], name: "index_categories_on_repository_id", using: :btree

  create_table "category_options", force: :cascade do |t|
    t.string   "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "cc_moneys", force: :cascade do |t|
    t.integer  "user_id"
    t.integer  "volunteer_task_id"
    t.integer  "cc"
    t.datetime "created_at",            null: false
    t.datetime "updated_at",            null: false
    t.integer  "proficient_project_id"
    t.integer  "order_id"
    t.integer  "discount_code_id"
  end

  add_index "cc_moneys", ["discount_code_id"], name: "index_cc_moneys_on_discount_code_id", using: :btree
  add_index "cc_moneys", ["order_id"], name: "index_cc_moneys_on_order_id", using: :btree
  add_index "cc_moneys", ["proficient_project_id"], name: "index_cc_moneys_on_proficient_project_id", using: :btree

  create_table "certifications", force: :cascade do |t|
    t.integer  "user_id"
    t.datetime "created_at",          null: false
    t.datetime "updated_at",          null: false
    t.integer  "training_session_id"
  end

  add_index "certifications", ["user_id"], name: "index_certifications_on_user_id", using: :btree

  create_table "comments", force: :cascade do |t|
    t.integer  "user_id"
    t.integer  "repository_id"
    t.text     "content"
    t.integer  "upvote",        default: 0
    t.datetime "created_at",                null: false
    t.datetime "updated_at",                null: false
    t.string   "username"
  end

  add_index "comments", ["repository_id"], name: "index_comments_on_repository_id", using: :btree
  add_index "comments", ["user_id"], name: "index_comments_on_user_id", using: :btree

  create_table "discount_codes", force: :cascade do |t|
    t.integer  "price_rule_id"
    t.integer  "user_id"
    t.string   "shopify_discount_code_id"
    t.string   "code"
    t.integer  "usage_count"
    t.datetime "created_at",               null: false
    t.datetime "updated_at",               null: false
  end

  add_index "discount_codes", ["price_rule_id"], name: "index_discount_codes_on_price_rule_id", using: :btree
  add_index "discount_codes", ["user_id"], name: "index_discount_codes_on_user_id", using: :btree

  create_table "equipment", force: :cascade do |t|
    t.integer  "repository_id"
    t.string   "name"
    t.datetime "created_at",    null: false
    t.datetime "updated_at",    null: false
  end

  add_index "equipment", ["repository_id"], name: "index_equipment_on_repository_id", using: :btree

  create_table "equipment_options", force: :cascade do |t|
    t.string   "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "exam_questions", force: :cascade do |t|
    t.integer  "exam_id"
    t.integer  "question_id"
    t.datetime "created_at",  null: false
    t.datetime "updated_at",  null: false
  end

  create_table "exam_responses", force: :cascade do |t|
    t.integer  "exam_question_id"
    t.integer  "answer_id"
    t.boolean  "correct"
    t.datetime "created_at",       null: false
    t.datetime "updated_at",       null: false
  end

  create_table "exams", force: :cascade do |t|
    t.integer  "user_id"
    t.string   "category"
    t.datetime "created_at",                                  null: false
    t.datetime "updated_at",                                  null: false
    t.string   "status",              default: "not started"
    t.integer  "score"
    t.integer  "training_session_id"
    t.datetime "expired_at"
  end

  create_table "lab_sessions", force: :cascade do |t|
    t.integer  "user_id"
    t.datetime "sign_in_time"
    t.datetime "sign_out_time"
    t.datetime "created_at",    null: false
    t.datetime "updated_at",    null: false
    t.string   "mac_address"
    t.integer  "space_id"
  end

  add_index "lab_sessions", ["space_id"], name: "index_lab_sessions_on_space_id", using: :btree
  add_index "lab_sessions", ["user_id"], name: "index_lab_sessions_on_user_id", using: :btree

  create_table "likes", force: :cascade do |t|
    t.integer  "user_id"
    t.integer  "repository_id"
    t.datetime "created_at",    null: false
    t.datetime "updated_at",    null: false
  end

  add_index "likes", ["repository_id"], name: "index_likes_on_repository_id", using: :btree
  add_index "likes", ["user_id"], name: "index_likes_on_user_id", using: :btree

  create_table "order_items", force: :cascade do |t|
    t.integer  "proficient_project_id"
    t.integer  "order_id"
    t.decimal  "unit_price",            precision: 12, scale: 3
    t.decimal  "total_price",           precision: 12, scale: 3
    t.integer  "quantity"
    t.datetime "created_at",                                                             null: false
    t.datetime "updated_at",                                                             null: false
    t.string   "status",                                         default: "In progress"
  end

  create_table "order_statuses", force: :cascade do |t|
    t.string   "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "orders", force: :cascade do |t|
    t.integer  "order_status_id"
    t.decimal  "subtotal",        precision: 12, scale: 3
    t.decimal  "total",           precision: 12, scale: 3
    t.datetime "created_at",                               null: false
    t.datetime "updated_at",                               null: false
    t.integer  "user_id"
  end

  create_table "photos", force: :cascade do |t|
    t.integer  "repository_id"
    t.datetime "created_at",            null: false
    t.datetime "updated_at",            null: false
    t.string   "image_file_name"
    t.string   "image_content_type"
    t.integer  "image_file_size"
    t.datetime "image_updated_at"
    t.integer  "height"
    t.integer  "width"
    t.integer  "proficient_project_id"
  end

  add_index "photos", ["repository_id"], name: "index_photos_on_repository_id", using: :btree

  create_table "pi_readers", force: :cascade do |t|
    t.string   "pi_mac_address"
    t.string   "pi_location"
    t.datetime "created_at",     null: false
    t.datetime "updated_at",     null: false
    t.integer  "space_id"
  end

  add_index "pi_readers", ["space_id"], name: "index_pi_readers_on_space_id", using: :btree

  create_table "price_rules", force: :cascade do |t|
    t.string   "shopify_price_rule_id"
    t.string   "title"
    t.integer  "value"
    t.integer  "cc"
    t.integer  "usage_limit"
    t.datetime "created_at",            null: false
    t.datetime "updated_at",            null: false
  end

  create_table "print_orders", force: :cascade do |t|
    t.integer  "user_id"
    t.boolean  "approved"
    t.boolean  "printed"
    t.text     "comments"
    t.datetime "created_at",                          null: false
    t.datetime "updated_at",                          null: false
    t.string   "file_file_name"
    t.string   "file_content_type"
    t.integer  "file_file_size"
    t.datetime "file_updated_at"
    t.float    "quote"
    t.integer  "staff_id"
    t.boolean  "user_approval"
    t.text     "staff_comments"
    t.boolean  "expedited"
    t.integer  "order_type",              default: 0
    t.text     "email"
    t.text     "name"
    t.datetime "timestamp_approved"
    t.string   "final_file_file_name"
    t.string   "final_file_content_type"
    t.integer  "final_file_file_size"
    t.datetime "final_file_updated_at"
    t.float    "grams"
    t.float    "service_charge"
    t.float    "price_per_hour"
    t.float    "price_per_gram"
    t.float    "material_cost"
    t.boolean  "sst"
    t.text     "material"
    t.float    "grams2"
    t.float    "price_per_gram2"
    t.float    "hours"
  end

  create_table "printer_sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer  "user_id"
    t.integer  "printer_id"
  end

  create_table "printers", force: :cascade do |t|
    t.datetime "created_at",                      null: false
    t.datetime "updated_at",                      null: false
    t.string   "model"
    t.string   "number"
    t.string   "status",       default: "true"
    t.string   "availability", default: "true"
    t.string   "color",        default: "FF0000"
    t.string   "rfid"
  end

  create_table "proficient_projects", force: :cascade do |t|
    t.integer  "training_id"
    t.string   "title"
    t.text     "description"
    t.datetime "created_at",                             null: false
    t.datetime "updated_at",                             null: false
    t.string   "level",             default: "Beginner"
    t.integer  "cc",                default: 0
    t.boolean  "proficient",        default: true
    t.integer  "badge_template_id"
  end

  add_index "proficient_projects", ["badge_template_id"], name: "index_proficient_projects_on_badge_template_id", using: :btree

  create_table "proficient_projects_users", id: false, force: :cascade do |t|
    t.integer "user_id",               null: false
    t.integer "proficient_project_id", null: false
  end

  create_table "programs", force: :cascade do |t|
    t.integer  "user_id"
    t.string   "program_type"
    t.datetime "created_at",   null: false
    t.datetime "updated_at",   null: false
  end

  create_table "project_joins", force: :cascade do |t|
    t.integer  "user_id"
    t.integer  "project_proposal_id"
    t.datetime "created_at",          null: false
    t.datetime "updated_at",          null: false
  end

  create_table "project_proposals", force: :cascade do |t|
    t.integer  "user_id"
    t.integer  "admin_id"
    t.integer  "approved"
    t.string   "title"
    t.text     "description"
    t.string   "youtube_link"
    t.datetime "created_at",                                      null: false
    t.datetime "updated_at",                                      null: false
    t.string   "username"
    t.string   "email"
    t.string   "client"
    t.string   "area",                  default: [],                           array: true
    t.string   "client_type"
    t.string   "client_interest"
    t.string   "client_background"
    t.string   "supervisor_background"
    t.text     "equipments",            default: "Not informed."
  end

  create_table "project_requirements", force: :cascade do |t|
    t.integer  "proficient_project_id"
    t.integer  "required_project_id"
    t.datetime "created_at",            null: false
    t.datetime "updated_at",            null: false
  end

  create_table "questions", force: :cascade do |t|
    t.integer  "user_id"
    t.text     "description"
    t.datetime "created_at",         null: false
    t.datetime "updated_at",         null: false
    t.string   "image_file_name"
    t.string   "image_content_type"
    t.integer  "image_file_size"
    t.datetime "image_updated_at"
    t.integer  "training_id"
  end

  create_table "repo_files", force: :cascade do |t|
    t.integer  "repository_id"
    t.datetime "created_at",            null: false
    t.datetime "updated_at",            null: false
    t.string   "file_file_name"
    t.string   "file_content_type"
    t.integer  "file_file_size"
    t.datetime "file_updated_at"
    t.integer  "proficient_project_id"
  end

  add_index "repo_files", ["repository_id"], name: "index_repo_files_on_repository_id", using: :btree

  create_table "repositories", force: :cascade do |t|
    t.integer  "user_id"
    t.string   "title"
    t.string   "description"
    t.datetime "created_at",                          null: false
    t.datetime "updated_at",                          null: false
    t.string   "category"
    t.string   "license"
    t.string   "github"
    t.string   "github_url"
    t.integer  "like",                default: 0
    t.string   "user_username"
    t.integer  "make_id"
    t.integer  "make",                default: 0
    t.string   "slug"
    t.string   "share_type"
    t.string   "password"
    t.boolean  "featured",            default: false
    t.string   "youtube_link"
    t.integer  "project_proposal_id"
  end

  add_index "repositories", ["user_id"], name: "index_repositories_on_user_id", using: :btree

  create_table "repositories_users", id: false, force: :cascade do |t|
    t.integer "user_id",       null: false
    t.integer "repository_id", null: false
  end

  create_table "require_trainings", force: :cascade do |t|
    t.integer  "volunteer_task_id"
    t.integer  "training_id"
    t.datetime "created_at",        null: false
    t.datetime "updated_at",        null: false
  end

  create_table "rfids", force: :cascade do |t|
    t.integer  "user_id"
    t.string   "card_number"
    t.datetime "created_at",  null: false
    t.datetime "updated_at",  null: false
    t.string   "mac_address"
  end

  add_index "rfids", ["user_id"], name: "index_rfids_on_user_id", using: :btree

  create_table "sd_signins", force: :cascade do |t|
    t.integer  "printer_id"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "skills", force: :cascade do |t|
    t.integer  "user_id"
    t.string   "printing",        default: "No Experience"
    t.string   "laser_cutting",   default: "No Experience"
    t.string   "virtual_reality", default: "No Experience"
    t.string   "arduino",         default: "No Experience"
    t.string   "embroidery",      default: "No Experience"
    t.datetime "created_at",                                null: false
    t.datetime "updated_at",                                null: false
    t.boolean  "active",          default: true
    t.string   "soldering",       default: "No Experience"
  end

  create_table "spaces", force: :cascade do |t|
    t.string   "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "spaces_trainings", id: false, force: :cascade do |t|
    t.integer "space_id",    null: false
    t.integer "training_id", null: false
  end

  create_table "training_sessions", force: :cascade do |t|
    t.integer  "training_id"
    t.integer  "user_id"
    t.datetime "created_at",                       null: false
    t.datetime "updated_at",                       null: false
    t.string   "course"
    t.integer  "space_id"
    t.string   "level",       default: "Beginner"
  end

  add_index "training_sessions", ["training_id"], name: "index_training_sessions_on_training_id", using: :btree
  add_index "training_sessions", ["user_id"], name: "index_training_sessions_on_user_id", using: :btree

  create_table "training_sessions_users", id: false, force: :cascade do |t|
    t.integer "training_session_id"
    t.integer "user_id"
  end

  add_index "training_sessions_users", ["training_session_id"], name: "index_training_sessions_users_on_training_session_id", using: :btree
  add_index "training_sessions_users", ["user_id"], name: "index_training_sessions_users_on_user_id", using: :btree

  create_table "trainings", force: :cascade do |t|
    t.string   "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer  "space_id"
  end

  add_index "trainings", ["space_id"], name: "index_trainings_on_space_id", using: :btree

  create_table "upvotes", force: :cascade do |t|
    t.integer  "user_id"
    t.integer  "comment_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean  "downvote"
  end

  add_index "upvotes", ["comment_id"], name: "index_upvotes_on_comment_id", using: :btree
  add_index "upvotes", ["user_id"], name: "index_upvotes_on_user_id", using: :btree

  create_table "users", force: :cascade do |t|
    t.string   "username"
    t.string   "password"
    t.string   "url"
    t.datetime "created_at",                                             null: false
    t.datetime "updated_at",                                             null: false
    t.text     "description"
    t.string   "email"
    t.string   "avatar_file_name"
    t.string   "avatar_content_type"
    t.integer  "avatar_file_size"
    t.datetime "avatar_updated_at"
    t.string   "access_token"
    t.string   "name"
    t.string   "gender"
    t.string   "faculty"
    t.string   "use"
    t.integer  "reputation",                    default: 0
    t.string   "role",                          default: "regular_user"
    t.boolean  "terms_and_conditions"
    t.string   "program"
    t.integer  "student_id"
    t.string   "how_heard_about_us"
    t.string   "identity"
    t.string   "year_of_study"
    t.boolean  "read_and_accepted_waiver_form", default: false
    t.boolean  "active",                        default: true
    t.datetime "last_seen_at"
    t.integer  "wallet",                        default: 0
  end

  create_table "videos", force: :cascade do |t|
    t.integer  "proficient_project_id"
    t.datetime "created_at",                            null: false
    t.datetime "updated_at",                            null: false
    t.string   "video_file_name"
    t.string   "video_content_type"
    t.integer  "video_file_size"
    t.datetime "video_updated_at"
    t.string   "direct_upload_url",                     null: false
    t.boolean  "processed",             default: false, null: false
  end

  add_index "videos", ["proficient_project_id"], name: "index_videos_on_proficient_project_id", using: :btree

  create_table "volunteer_hours", force: :cascade do |t|
    t.integer  "volunteer_task_id",                                       null: false
    t.integer  "user_id",                                                 null: false
    t.datetime "date_of_task"
    t.decimal  "total_time",        precision: 9, scale: 2, default: 0.0
    t.datetime "created_at",                                              null: false
    t.datetime "updated_at",                                              null: false
    t.boolean  "approval"
  end

  create_table "volunteer_requests", force: :cascade do |t|
    t.text     "interests",       default: ""
    t.datetime "created_at",                                null: false
    t.datetime "updated_at",                                null: false
    t.integer  "user_id"
    t.boolean  "approval"
    t.integer  "space_id"
    t.string   "printing",        default: "No Experience"
    t.string   "laser_cutting",   default: "No Experience"
    t.string   "virtual_reality", default: "No Experience"
    t.string   "arduino",         default: "No Experience"
    t.string   "embroidery",      default: "No Experience"
    t.string   "soldering",       default: "No Experience"
  end

  create_table "volunteer_task_joins", force: :cascade do |t|
    t.integer  "user_id"
    t.integer  "volunteer_task_id"
    t.string   "user_type",         default: "Volunteer"
    t.datetime "created_at",                              null: false
    t.datetime "updated_at",                              null: false
    t.boolean  "active",            default: true
  end

  create_table "volunteer_task_requests", force: :cascade do |t|
    t.integer  "user_id"
    t.integer  "volunteer_task_id"
    t.boolean  "approval"
    t.datetime "created_at",        null: false
    t.datetime "updated_at",        null: false
  end

  create_table "volunteer_tasks", force: :cascade do |t|
    t.string   "title",                               default: ""
    t.text     "description",                         default: ""
    t.integer  "user_id"
    t.datetime "created_at",                                            null: false
    t.datetime "updated_at",                                            null: false
    t.string   "status",                              default: "open"
    t.integer  "space_id"
    t.integer  "joins",                               default: 1
    t.string   "category",                            default: "Other"
    t.integer  "cc",                                  default: 0
    t.decimal  "hours",       precision: 5, scale: 2, default: 0.0
  end

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
