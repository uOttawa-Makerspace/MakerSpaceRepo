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

ActiveRecord::Schema.define(version: 20170821221608) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "categories", force: :cascade do |t|
    t.integer  "repository_id"
    t.string   "name"
    t.datetime "created_at",         null: false
    t.datetime "updated_at",         null: false
    t.integer  "category_option_id"
    t.index ["category_option_id"], name: "index_categories_on_category_option_id", using: :btree
    t.index ["repository_id"], name: "index_categories_on_repository_id", using: :btree
  end

  create_table "category_options", force: :cascade do |t|
    t.string   "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "certifications", force: :cascade do |t|
    t.integer  "user_id"
    t.datetime "created_at",          null: false
    t.datetime "updated_at",          null: false
    t.integer  "training_session_id"
    t.index ["user_id"], name: "index_certifications_on_user_id", using: :btree
  end

  create_table "comments", force: :cascade do |t|
    t.integer  "user_id"
    t.integer  "repository_id"
    t.text     "content"
    t.integer  "upvote",        default: 0
    t.datetime "created_at",                null: false
    t.datetime "updated_at",                null: false
    t.string   "username"
    t.index ["repository_id"], name: "index_comments_on_repository_id", using: :btree
    t.index ["user_id"], name: "index_comments_on_user_id", using: :btree
  end

  create_table "equipment", force: :cascade do |t|
    t.integer  "repository_id"
    t.string   "name"
    t.datetime "created_at",    null: false
    t.datetime "updated_at",    null: false
    t.index ["repository_id"], name: "index_equipment_on_repository_id", using: :btree
  end

  create_table "equipment_options", force: :cascade do |t|
    t.string   "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "lab_sessions", force: :cascade do |t|
    t.integer  "user_id"
    t.datetime "sign_in_time"
    t.datetime "sign_out_time"
    t.datetime "created_at",    null: false
    t.datetime "updated_at",    null: false
    t.string   "mac_address"
    t.integer  "pi_reader_id"
    t.index ["pi_reader_id"], name: "index_lab_sessions_on_pi_reader_id", using: :btree
    t.index ["user_id"], name: "index_lab_sessions_on_user_id", using: :btree
  end

  create_table "likes", force: :cascade do |t|
    t.integer  "user_id"
    t.integer  "repository_id"
    t.datetime "created_at",    null: false
    t.datetime "updated_at",    null: false
    t.index ["repository_id"], name: "index_likes_on_repository_id", using: :btree
    t.index ["user_id"], name: "index_likes_on_user_id", using: :btree
  end

  create_table "photos", force: :cascade do |t|
    t.integer  "repository_id"
    t.datetime "created_at",         null: false
    t.datetime "updated_at",         null: false
    t.string   "image_file_name"
    t.string   "image_content_type"
    t.integer  "image_file_size"
    t.datetime "image_updated_at"
    t.integer  "height"
    t.integer  "width"
    t.index ["repository_id"], name: "index_photos_on_repository_id", using: :btree
  end

  create_table "pi_readers", force: :cascade do |t|
    t.string   "pi_mac_address"
    t.string   "pi_location"
    t.datetime "created_at",     null: false
    t.datetime "updated_at",     null: false
    t.integer  "space_id"
    t.index ["space_id"], name: "index_pi_readers_on_space_id", using: :btree
  end

  create_table "repo_files", force: :cascade do |t|
    t.integer  "repository_id"
    t.datetime "created_at",        null: false
    t.datetime "updated_at",        null: false
    t.string   "file_file_name"
    t.string   "file_content_type"
    t.integer  "file_file_size"
    t.datetime "file_updated_at"
    t.index ["repository_id"], name: "index_repo_files_on_repository_id", using: :btree
  end

  create_table "repositories", force: :cascade do |t|
    t.integer  "user_id"
    t.string   "title"
    t.string   "description"
    t.datetime "created_at",                null: false
    t.datetime "updated_at",                null: false
    t.string   "category"
    t.string   "license"
    t.string   "github"
    t.string   "github_url"
    t.integer  "like",          default: 0
    t.string   "user_username"
    t.integer  "make_id"
    t.integer  "make",          default: 0
    t.string   "slug"
    t.index ["user_id"], name: "index_repositories_on_user_id", using: :btree
  end

  create_table "rfids", force: :cascade do |t|
    t.integer  "user_id"
    t.string   "card_number"
    t.datetime "created_at",  null: false
    t.datetime "updated_at",  null: false
    t.string   "mac_address"
    t.index ["user_id"], name: "index_rfids_on_user_id", using: :btree
  end

  create_table "spaces", force: :cascade do |t|
    t.string   "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "training_sessions", force: :cascade do |t|
    t.integer  "training_id"
    t.integer  "user_id"
    t.datetime "created_at",  null: false
    t.datetime "updated_at",  null: false
    t.string   "course"
    t.index ["training_id"], name: "index_training_sessions_on_training_id", using: :btree
    t.index ["user_id"], name: "index_training_sessions_on_user_id", using: :btree
  end

  create_table "training_sessions_users", id: false, force: :cascade do |t|
    t.integer "training_session_id"
    t.integer "user_id"
    t.index ["training_session_id"], name: "index_training_sessions_users_on_training_session_id", using: :btree
    t.index ["user_id"], name: "index_training_sessions_users_on_user_id", using: :btree
  end

  create_table "trainings", force: :cascade do |t|
    t.string   "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer  "space_id"
    t.index ["space_id"], name: "index_trainings_on_space_id", using: :btree
  end

  create_table "upvotes", force: :cascade do |t|
    t.integer  "user_id"
    t.integer  "comment_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean  "downvote"
    t.index ["comment_id"], name: "index_upvotes_on_comment_id", using: :btree
    t.index ["user_id"], name: "index_upvotes_on_user_id", using: :btree
  end

  create_table "users", force: :cascade do |t|
    t.string   "username"
    t.string   "password"
    t.string   "url"
    t.datetime "created_at",                                    null: false
    t.datetime "updated_at",                                    null: false
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
    t.integer  "reputation",           default: 0
    t.string   "role",                 default: "regular_user"
    t.boolean  "terms_and_conditions"
    t.integer  "student_id"
    t.string   "program"
    t.string   "how_heard_about_us"
    t.string   "identity"
    t.string   "year_of_study"
  end

  add_foreign_key "categories", "category_options"
  add_foreign_key "categories", "repositories"
  add_foreign_key "certifications", "users"
  add_foreign_key "comments", "repositories"
  add_foreign_key "comments", "users"
  add_foreign_key "equipment", "repositories"
  add_foreign_key "lab_sessions", "pi_readers"
  add_foreign_key "likes", "repositories"
  add_foreign_key "likes", "users"
  add_foreign_key "photos", "repositories"
  add_foreign_key "pi_readers", "spaces"
  add_foreign_key "repo_files", "repositories"
  add_foreign_key "repositories", "users"
  add_foreign_key "rfids", "users"
  add_foreign_key "training_sessions", "trainings"
  add_foreign_key "training_sessions", "users"
  add_foreign_key "trainings", "spaces"
  add_foreign_key "upvotes", "comments"
  add_foreign_key "upvotes", "users"
end
