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
    allow_new_programs = params[:allow_new_programs]
    file = params[:file]
    file_ext = File.extname(file.original_filename)
    raise "Unknown file extension: #{file_ext}" unless file_ext == ".csv"

    test_data = CSV.read(file.to_io, headers: true)

    # test header
    expected_header = %w[program level faculty department]
    unless test_data.headers == expected_header
      raise "Wrong header, expecting #{expected_header} but found #{test_data.headers}"
    end

    # test each row for existence, trim and watch out for whitespace
    # lineno skip headers
    current_faculties = ProgramList.faculty_list
    test_data
      .filter
      .with_index(2) do |row, lineno|
        expected_header.each do |k|
          if row[k].blank?
            raise "Error line number #{lineno}, column #{k} is empty"
          end

          row[k] = row[k].squish # remove possible BOM issues
        end

        # if the university adds a new faculty, this will break,
        # mostly designed to catch any user errors
        unless allow_new_programs || current_faculties.include?(row["faculty"])
          raise "Unknown faculty #{row["faculty"]} at line number #{lineno}"
        end
      end

    # Save to assets
    File.open(Rails.root.join("lib/assets/programs.csv"), "w") do |newfile|
      newfile.write(test_data.to_csv) # write out as string
    end
  rescue StandardError => e # Grab any error, display to user
    flash[:alert] = "Programs upload error: #{e}"
  else
    flash[:notice] = "Upload complete, #{test_data.count} programs found"
  ensure
    redirect_to admin_uni_programs_index_path
  end
end
