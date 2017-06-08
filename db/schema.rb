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

ActiveRecord::Schema.define(version: 20170605181436) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "categories", force: :cascade do |t|
    t.integer  "repository_id"
    t.string   "name"
    t.datetime "created_at",    null: false
    t.datetime "updated_at",    null: false
  end

  add_index "categories", ["repository_id"], name: "index_categories_on_repository_id", using: :btree

  create_table "category_options", force: :cascade do |t|
    t.string   "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "certifications", force: :cascade do |t|
    t.integer  "user_id"
    t.string   "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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

  create_table "lab_sessions", force: :cascade do |t|
    t.integer  "user_id"
    t.datetime "sign_in_time"
    t.datetime "sign_out_time"
    t.datetime "created_at",    null: false
    t.datetime "updated_at",    null: false
    t.string   "mac_address"
  end

  add_index "lab_sessions", ["user_id"], name: "index_lab_sessions_on_user_id", using: :btree

  create_table "likes", force: :cascade do |t|
    t.integer  "user_id"
    t.integer  "repository_id"
    t.datetime "created_at",    null: false
    t.datetime "updated_at",    null: false
  end

  add_index "likes", ["repository_id"], name: "index_likes_on_repository_id", using: :btree
  add_index "likes", ["user_id"], name: "index_likes_on_user_id", using: :btree

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
  end

  add_index "photos", ["repository_id"], name: "index_photos_on_repository_id", using: :btree

  create_table "pi_readers", force: :cascade do |t|
    t.string   "pi_mac_address"
    t.string   "pi_location"
    t.datetime "created_at",     null: false
    t.datetime "updated_at",     null: false
  end

  create_table "repo_files", force: :cascade do |t|
    t.integer  "repository_id"
    t.datetime "created_at",        null: false
    t.datetime "updated_at",        null: false
    t.string   "file_file_name"
    t.string   "file_content_type"
    t.integer  "file_file_size"
    t.datetime "file_updated_at"
  end

  add_index "repo_files", ["repository_id"], name: "index_repo_files_on_repository_id", using: :btree

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
  end

  add_index "repositories", ["user_id"], name: "index_repositories_on_user_id", using: :btree

  create_table "rfids", force: :cascade do |t|
    t.integer  "user_id"
    t.string   "card_number"
    t.datetime "created_at",  null: false
    t.datetime "updated_at",  null: false
    t.string   "mac_address"
  end

  add_index "rfids", ["user_id"], name: "index_rfids_on_user_id", using: :btree

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
    t.string   "location"
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
    t.string   "program"
    t.integer  "student_id"
    t.string   "how_heard_about_us"
  end

  add_foreign_key "categories", "repositories"
  add_foreign_key "certifications", "users"
  add_foreign_key "comments", "repositories"
  add_foreign_key "comments", "users"
  add_foreign_key "equipment", "repositories"
  add_foreign_key "likes", "repositories"
  add_foreign_key "likes", "users"
  add_foreign_key "photos", "repositories"
  add_foreign_key "repo_files", "repositories"
  add_foreign_key "repositories", "users"
  add_foreign_key "rfids", "users"
  add_foreign_key "upvotes", "comments"
  add_foreign_key "upvotes", "users"
end
