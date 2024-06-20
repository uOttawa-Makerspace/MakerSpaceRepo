# frozen_string_literal: true

class ProgramList
  # TODO: figure out a better way to do this
  def self.fetch_all
    @programs = []
    File
      .read("#{Rails.root}/lib/assets/programs.txt")
      .each_line { |line| @programs << line.chop }
    @programs
  end

  def self.fetch_all_csv
    program, level, faculty, department = *(0..3) # Assign indexes
    #@programs =
    CSV.read(Rails.root.join("lib/assets/programs.csv"), headers: true)

    @programs_by_faculty = {}
    @programs.each do |prog|
      program, level, faculty, department = prog.values_at *(0..3) # Assign indexes
      @programs_by_faculty[faculty] ||= []
      @programs_by_faculty[faculty] << program
    end
    #@programs
  end

  def self.fetch_by_faculty
    programs =
      CSV.read(Rails.root.join("lib/assets/programs.csv"), headers: true)

    programs_by_faculty = {}
    programs.each do |prog|
      program, level, faculty, department = prog.values_at *(0..3) # Assign indexes
      programs_by_faculty[faculty] ||= []
      programs_by_faculty[faculty] << program
    end
    programs_by_faculty
  end

  def categorize_program(program)
    # https://developer.snapappointments.com/bootstrap-select/options/
  end
end
