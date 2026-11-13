# frozen_string_literal: true

# What the uOEng student-information service last said about a user: student number (emplid),
# faculty, program code, level, and the full-time and current-semester flags. One row per user,
# written by the faculty membership check after an answer about this user. The user's own profile
# fields stay as the user (or an admin) entered them; this record sits beside them.
class UoengProfile < ApplicationRecord
  # uOEng faculty codes the app knows; any other code is kept as a code with no faculty.
  FACULTIES = { "GENIE" => "Engineering" }.freeze
  # uOEng program levels the app knows; any other level is left blank.
  LEVELS = { "undergraduate" => "undergrad", "graduate" => "grad" }.freeze
  SOURCES = %w[student_number email].freeze

  belongs_to :user

  validates :level, inclusion: { in: LEVELS.values }, allow_nil: true
  validates :source, inclusion: { in: SOURCES }

  # Writes the user's row from one answer, or replaces it when there is one already. A single
  # upsert on the unique user_id, so two checks at once leave one row, and running it again with
  # the same answer changes nothing but checked_at.
  def self.record!(user, answer, source:)
    upsert(
      { user_id: user.id, source: source, checked_at: Time.current, **fields_from(answer) },
      unique_by: :user_id
    )
  end

  # Only the fields the record keeps; nothing else in the answer is read.
  def self.fields_from(answer)
    faculty_code = text(answer["faculty"])
    {
      emplid: text(answer["emplid"]) || text(answer["student_number"]),
      faculty_code: faculty_code,
      faculty: FACULTIES[faculty_code],
      program_code: text(answer["program"]),
      level: LEVELS[answer["program_level"]],
      full_time: flag(answer["fulltime"]),
      current_semester: flag(answer["student_this_semester"])
    }
  end

  def self.text(value)
    value.to_s.strip.presence if value.is_a?(String) || value.is_a?(Integer)
  end

  def self.flag(value)
    value if [true, false].include?(value)
  end

  private_class_method :fields_from, :text, :flag
end
