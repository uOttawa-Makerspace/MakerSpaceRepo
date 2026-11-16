# frozen_string_literal: true

require "csv"

# Brings the programs table in line with a programs csv (header: program, level, faculty, department).
#
# A program is identified by its program, level and faculty. Programs in the file that are new are added, listed ones
# whose department changed are updated in place, and active programs the file no longer lists are marked inactive;
# nothing is deleted. Importing the same file again changes nothing. A program listed twice in the file counts once.
class UniProgram::Import
  class Invalid < StandardError; end

  HEADER = %w[program level faculty department].freeze
  KEY = %w[program level faculty].freeze

  Result = Struct.new(:found, :added, :updated, :retired, :restored, keyword_init: true)

  def initialize(csv, allow_new_faculties: false)
    @rows = parse(csv)
    @allow_new_faculties = allow_new_faculties
  end

  # Raises Invalid, before any change, when the file is not usable.
  def run
    check_rows
    UniProgram.transaction do
      UniProgram.connection.execute("LOCK TABLE uni_programs IN SHARE ROW EXCLUSIVE MODE")
      apply
    end
  end

  private

  def parse(csv)
    table = CSV.parse(csv.dup.force_encoding(Encoding::UTF_8), headers: true)
    unless table.headers == HEADER
      raise Invalid, "Wrong header, expecting #{HEADER} but found #{table.headers}"
    end

    table.each_with_index.map { |row, index| [row.to_h.transform_values { |v| v&.squish }, index + 2] }
  end

  def check_rows
    faculties = UniProgram.all_faculties
    @rows.each do |row, lineno|
      HEADER.each { |column| raise Invalid, "Error line number #{lineno}, column #{column} is empty" if row[column].blank? }
      next if @allow_new_faculties || faculties.include?(row["faculty"])

      raise Invalid, "Unknown faculty #{row["faculty"]} at line number #{lineno}"
    end
  end

  def apply
    listed = @rows.map(&:first).uniq { |row| row.values_at(*KEY) }
    result = Result.new(found: @rows.size, added: 0, updated: 0, retired: 0, restored: 0)
    active = UniProgram.where(active: true).pluck(*KEY, :department).to_h { |*key, department| [key, department] }
    listed.each { |row| place(row, active, result) }
    retire(active.keys - listed.map { |row| row.values_at(*KEY) }, result)
    result
  end

  def place(row, active, result)
    key = row.values_at(*KEY)
    if !active.key?(key)
      restore_or_add(row, result)
    elsif active[key] != row["department"]
      UniProgram.where(KEY.zip(key).to_h).where(active: true).update_all(department: row["department"])
      result.updated += 1
    end
  end

  def restore_or_add(row, result)
    if restore(row)
      result.restored += 1
    else
      UniProgram.create!(row.slice(*HEADER))
      result.added += 1
    end
  end

  # Brings one inactive row for the program back, with the department of the file.
  def restore(row)
    UniProgram.connection.exec_update(UniProgram.sanitize_sql_array([<<~SQL.squish, row["department"], *row.values_at(*KEY)])) == 1
      UPDATE uni_programs SET active = TRUE, department = ?
      WHERE ctid = (SELECT ctid FROM uni_programs WHERE NOT active AND program = ? AND level = ? AND faculty = ? LIMIT 1)
    SQL
  end

  def retire(keys, result)
    keys.each do |key|
      result.retired += UniProgram.where(KEY.zip(key).to_h).where(active: true).update_all(active: false)
    end
  end
end
