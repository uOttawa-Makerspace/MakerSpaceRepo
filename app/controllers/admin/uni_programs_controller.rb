# frozen_string_literal: true

class Admin::UniProgramsController < AdminAreaController
  @cached_programs = nil

  def index
    @uni_programs = ProgramList.fetch_all_csv
  end

  def current_programs
    # program_data = CSV.read("#{Rails.root}/lib/assets/programs.csv")
    # send_data program_data, type: 'text/csv', filename: 'huh.csv'
    send_file "#{Rails.root}/lib/assets/programs.csv"
  end

  # Takes in a csv file, parses and verifies all
  def import_programs
    file = params[:file]
    file_ext = File.extname(file.original_filename)
    raise "Unknown file type: #{file_ext}" unless file_ext == ".csv"

    test_data = CSV.new(file.to_io)

    # test header
    expected_header = %w[program level faculty department]
    unless test_data.shift.to_a == expected_header
      raise "Wrong header, expecting #{expected_header}"
    end

    # test each row for existence, trim and watch out for whitespace
    test_data.each do |row|
      expected_header
        .each
        .with_index(1) do |k, lineno|
          if row[k].nil? || row[k] == ""
            raise "Error line number #{lineno}, column #{k} is empty"
          end

          row[k] = row[k].squish # remove possible BOM issues
        end
    end

    flash[:notice] = "Upload complete"
    # Save to assets
    newfile.rewind
    File.open(Rails.root.join("lib/assets/programs.csv"), "w") do |newfile|
      newfile.write(file.read)
    end
    redirect_to admin_uni_programs_index_path
  end
end
