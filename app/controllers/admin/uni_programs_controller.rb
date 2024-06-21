# frozen_string_literal: true

class Admin::UniProgramsController < AdminAreaController
  @cached_programs = nil

  def index
    @uni_programs = fetch_programs
  end

  def current_programs
    # program_data = CSV.read("#{Rails.root}/lib/assets/programs.csv")
    # send_data program_data, type: 'text/csv', filename: 'huh.csv'
    send_file "#{Rails.root}/lib/assets/programs.csv"
  end

  # Returns programs as a hash
  # TODO this sucks man, do we have to do a disk hit every time we
  # query programs?
  # TODO how does rails storage work?
  # NOTE this is just patchwork, because we store user program as a string
  # so this takes the string and attempts to categorize it.
  # a better plan would be a DB migration to a separate programs table.
  # FIXME don't call this programs, do something like uni_programs

  # from cache
  def fetch_programs
    if @cached_programs
      return @cached_programs # test cache
    end

    program, level, faculty, department = *(0..3) # Assign indexes
    @cached_programs =
      CSV
        .read(Rails.root.join("lib/assets/programs.csv"), headers: true)
        .group_by { |x| x[faculty] }
        .transform_values do |x|
          x.sort_by { |x| [x[level], x[department], x[program]] }
        end
    @cached_programs
  end
  # Takes in a csv file, parses and verifies all
  def import_programs
    begin
      # file = params[:file]

      flash[:notice] = "Upload complete"
      cached_programs = nil
    end
    redirect_to admin_programs_index_path
  end
end
