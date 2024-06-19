# frozen_string_literal: true

class Admin::ProgramsController < AdminAreaController
  def index
    @uni_programs = fetch_programs
  end

  def current_programs
    # program_data = CSV.read("#{Rails.root}/lib/assets/programs.csv")
    # send_data program_data, type: 'text/csv', filename: 'huh.csv'
    send_file "#{Rails.root}/lib/assets/programs.csv"
  end

  # Returns programs as a hash
  def fetch_programs
    program, level, faculty, department = *(0..3) # Assign indexes
    CSV.read(Rails.root.join('lib/assets/programs.csv'), headers: true)
       .group_by { |x| x[faculty] }
       .transform_values { |x| x.sort_by { |x| [x[level], x[department], x[program] ] } }
  end
  # Takes in a csv file, parses and verifies all
  # Colum
  def import_programs
    begin
    # file = params[:file]

    flash[:notice] = 'Upload complete'
    end
    redirect_to admin_programs_index_path
  end
end
