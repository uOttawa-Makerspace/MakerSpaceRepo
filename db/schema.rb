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

ActiveRecord::Schema.define(version: 20150620153444) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

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

  create_table "repositories", force: :cascade do |t|
    t.integer  "user_id"
    t.string   "title"
    t.string   "description"
    t.datetime "created_at",                null: false
    t.datetime "updated_at",                null: false
    t.string   "category"
    t.string   "license"
    t.string   "github"
    t.integer  "likes",         default: 0
    t.string   "github_url"
    t.integer  "like",          default: 0
    t.string   "user_username"
  end

  add_index "repositories", ["user_id"], name: "index_repositories_on_user_id", using: :btree

  create_table "tags", force: :cascade do |t|
    t.integer  "repository_id"
    t.string   "name"
    t.datetime "created_at",    null: false
    t.datetime "updated_at",    null: false
  end

  add_index "tags", ["repository_id"], name: "index_tags_on_repository_id", using: :btree

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
    t.string   "first_name"
    t.string   "last_name"
    t.string   "password"
    t.string   "url"
    t.string   "location"
    t.datetime "created_at",          null: false
    t.datetime "updated_at",          null: false
    t.text     "description"
    t.string   "email"
    t.string   "avatar_file_name"
    t.string   "avatar_content_type"
    t.integer  "avatar_file_size"
    t.datetime "avatar_updated_at"
    t.string   "access_token"
  end

  add_foreign_key "comments", "repositories"
  add_foreign_key "comments", "users"
  add_foreign_key "likes", "repositories"
  add_foreign_key "likes", "users"
  add_foreign_key "photos", "repositories"
  add_foreign_key "repositories", "users"
  add_foreign_key "tags", "repositories"
  add_foreign_key "upvotes", "comments"
  add_foreign_key "upvotes", "users"
end
