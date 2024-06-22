# frozen_string_literal: true

class ProgramList
  # TODO: figure out a better way to do this
  # FIXME remove all references to this
  def self.fetch_all
    @programs = []
    File
      .read("#{Rails.root}/lib/assets/programs.txt")
      .each_line { |line| @programs << line.chop }
    @programs
  end

  def self.faculty_fr_to_en(faculty)
    translation = {
      "Arts" => "Arts",
      "Éducation" => "Education",
      "Génie" => "Engineering",
      "Sciences de la santé" => "Health Sciences",
      "Droit civil" => "Civil Law",
      "Droit commun" => "Common Law",
      "Droit" => "Law",
      "Médecine" => "Medicine",
      "Sciences" => "Science",
      "Sciences sociales" => "Social Sciences",
      "École de gestion Telfer" => "Telfer School of Management"
    }
    translation[faculty]
  end

  def self.faculty_list
    fetch_all_csv["faculty"].uniq
  end

  def self.programs_by_faculty
    ProgramList
      .fetch_all_csv
      .group_by { |x| x["faculty"] } # Group by faculty
      .transform_values { |x| x.map { |x| x["program"] }.uniq } # Duplicates...
  end

  # This returns the CSV structure as is,
  # so you can do fetch_all_csv['faculty'].uniq to get faculties,
  # fetch_all_csv['program']
  # fetch_all_csv.select { |x| x['department'] == 'Chemical' }
  # fetch_all_csv['faculty'].tally
  # NOTE This returns duplicates, because some programs are listed
  # as both Bachelor's and PhD for some reason. Check docs for more info
  # program, level, faculty, department
  def self.fetch_all_csv
    CSV.read(Rails.root.join("lib/assets/programs.csv"), headers: true)
  end

  def categorize_program(program)
    # https://developer.snapappointments.com/bootstrap-select/options/
    raise NotImplementedError
  end
end
