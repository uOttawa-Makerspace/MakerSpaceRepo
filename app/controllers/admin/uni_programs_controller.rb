# frozen_string_literal: true

class Admin::UniProgramsController < AdminAreaController
  @cached_programs = nil

  def index
    @uni_programs = UniProgram.active
  end

  def current_programs
    file = Rails.root.join("lib/assets/programs.csv")
    return send_file(file, type: "text/csv") if file.exist?

    redirect_to admin_uni_programs_index_path, alert: I18n.t("errors.admin.uni_programs.programs_file_missing")
  end

  # Takes in a csv file, checks it and updates the programs from it; see UniProgram::Import.
  def import_programs
    file = params[:file]
    file_ext = File.extname(file.original_filename)
    raise "Unknown file extension: #{file_ext}" unless file_ext == ".csv"

    @result = UniProgram::Import.new(file.read, allow_new_faculties: params[:allow_new_programs].present?).run
  rescue StandardError => e # Grab any error, display to user
    flash[:alert] = "Programs upload error: #{e}"
  else
    flash[:notice] = upload_summary(@result)
  ensure
    redirect_to admin_uni_programs_index_path
  end

  private

  def upload_summary(result)
    "Upload complete, #{result.found} programs found " \
      "(#{result.added} added, #{result.updated} updated, #{result.restored} restored, #{result.retired} retired)"
  end
end
