# frozen_string_literal: true

class UniProgram < ApplicationRecord
  validates :program, presence: true

  # NOTE: This returns duplicates, because some programs are listed
  # as both Bachelor's and PhD for some reason. Check docs for more info
  default_scope { where.not(faculty: "") }
  scope :per_faculty, -> { group(:faculty) }

  def self.unique_programs
    distinct.pluck :program
  end

  def self.all_faculties
    distinct.pluck :faculty
  end

  # Returns a list of programs managed by each faculty
  def self.programs_by_faculty
    select(:program, :faculty)
      .group_by { |x| x["faculty"] } # Group by faculty
      .transform_values { |x| x.map { |x| x["program"] }.uniq } # Duplicates...
  end
end
