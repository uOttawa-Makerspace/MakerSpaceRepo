# The latest answer the uOEng student-information service gave about a user, one row per user. It
# is kept beside the user's own fields, which the check never changes. The unique index on user_id
# is what lets a card tap and a staff check running at once write one row (an upsert on it).
# emplid, the codes and the flags may be missing from an answer, so they may be null; level is
# undergrad or grad only, and source says how the user was looked up. users.id is a serial
# (integer), so user_id is an integer. New table with no existing data; rolling back drops it.
class CreateUoengProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :uoeng_profiles do |t|
      t.references :user, type: :integer, null: false, index: { unique: true }, foreign_key: { on_delete: :cascade }
      t.string :emplid
      t.string :faculty_code
      t.string :faculty
      t.string :program_code
      t.string :level
      t.boolean :full_time
      t.boolean :current_semester
      t.datetime :checked_at, null: false
      t.string :source, null: false
      t.timestamps
      t.check_constraint "level IN ('undergrad', 'grad')", name: "uoeng_profiles_level_known"
      t.check_constraint "source IN ('student_number', 'email')", name: "uoeng_profiles_source_known"
    end
  end
end
