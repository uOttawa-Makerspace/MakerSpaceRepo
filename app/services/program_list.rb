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

  def self.faculty_fr_to_en(_faculty)
    {
      arts: "Arts",
      civil_law: "Droit civil",
      common_law: "Droit commun",
      education: "Éducation",
      engineering: "Génie",
      health_sciences: "Sciences de la santé",
      medicine: "Médecine",
      science: "Sciences",
      social_sciences: "Sciences sociales",
      telfer: "École de gestion Telfer"
    }
  end

  def self.faculty_list
    _program, _level, faculty, _department = *(0..3) # Assign indexes
    fetch_all_csv.map { |x| x[faculty] }.uniq
  end

  def self.fetch_all_csv
    CSV.read(Rails.root.join("lib/assets/programs.csv"), headers: true)
  end

  def self.fetch_by_faculty
    programs = fetch_all_csv

    programs_by_faculty = {}
    programs.each do |prog|
      program, _level, faculty, _department = prog.values_at(*(0..3)) # Assign indexes
      programs_by_faculty[faculty] ||= []
      programs_by_faculty[faculty] << program
    end
    programs_by_faculty
  end

  def categorize_program(program)
    # https://developer.snapappointments.com/bootstrap-select/options/
  end
end
