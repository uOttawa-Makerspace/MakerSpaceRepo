# frozen_string_literal: true

class UniProgram < ApplicationRecord
  validates :program, presence: true

  # Shown when the reference row with no faculty is missing
  NO_PROGRAM_LABEL = "My program is not in the list"

  # NOTE: This returns duplicates, because some programs are listed
  # as both Bachelor's and PhD for some reason. Check docs for more info
  default_scope { where.not(faculty: "") }

  # Programs a later import no longer lists stay in the table as inactive, so users who chose them keep a program that
  # resolves to a department; pickers offer active programs only.
  scope :active, -> { where(active: true) }

  def self.no_program
    UniProgram.unscoped.find_by(faculty: "")&.program || NO_PROGRAM_LABEL
  end

  def self.unique_programs
    distinct.pluck :program
  end

  def self.all_faculties
    distinct.pluck :faculty
  end

  def self.all_departments
    distinct.pluck :department
  end

  # Returns a list of active programs managed by each faculty. The program named in keep (a user's current choice)
  # is listed too when it is no longer active, so a form does not drop it.
  def self.programs_by_faculty(keep: nil)
    listed = keep.present? ? active.or(where(program: keep)) : active
    listed
      .select(:program, :faculty)
      .group_by { |x| x["faculty"] } # Group by faculty
      .transform_values { |x| x.map { |x| x["program"] }.uniq } # Duplicates...
  end
end
