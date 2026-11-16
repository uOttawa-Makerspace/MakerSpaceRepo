# frozen_string_literal: true

class Admin::UniProgramsController < AdminAreaController
  @cached_programs = nil

  def index
    @uni_programs = UniProgram.active
    @retired_programs = UniProgram.where(active: false).order(:faculty, :program, :level)
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
    flash[:alert] = t("admin_area.uni_programs.flash.upload_error", error: e)
  else
    flash[:notice] = upload_summary(@result)
  ensure
    redirect_to admin_uni_programs_index_path
  end

  private

  def upload_summary(result)
    t("admin_area.uni_programs.flash.upload_complete", found: result.found, added: result.added,
                                                         updated: result.updated, restored: result.restored, retired: result.retired)
  end
end
