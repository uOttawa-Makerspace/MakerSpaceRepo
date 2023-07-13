# frozen_string_literal: true

class Admin::ReportGeneratorController < AdminAreaController
  layout "admin_area"
  require "date"

  def index
    @report_types = [
      ["Certifications", :certifications],
      ["New Projects", :new_projects],
      ["New Users", :new_users],
      ["Trainings", :trainings],
      ["Training Attendees", :training_attendees],
      ["Visitors", :visitors],
      ["Visits by Hour", :visits_by_hour],
      ["Kit purchased", :kit_purchased]
    ]

    if params[:report_type].present?
      set_date_specified

      case params[:report_type]
      when "visitors"
        visitors
      when "trainings"
        trainings
      when "certifications"
        certifications
      when "new_users"
        new_users
      when "training_attendees"
      when "new_projects"
        new_projects
      when "visits_by_hour"
      when "kit_purchased"
      else
        render plain: "Unknown report type", status: :bad_request
        return
      end
    end
  end

  def popular_hours
    @space = @user.lab_sessions&.last&.space || Space.first
    @spaces = Space.all.order(name: :asc)
    @weekdays = Date::DAYNAMES
  end

  def popular_hours_per_period
    if params[:start_date].blank? || params[:end_date].blank?
      redirect_to admin_report_generator_popular_hours_path,
                  alert:
                    "You need to select dates to get Popular Hours for a specific period."
    else
      @space = @user.lab_sessions&.last&.space || Space.first
      @spaces = Space.all.order(name: :asc)
      @weekdays = Date::DAYNAMES
      @info =
        PopularHour.popular_hours_per_period(
          params[:start_date].to_date,
          params[:end_date].to_date
        )
    end
  end

  def generate
    range_type = params[:range_type]
    term = params[:term]
    year = params[:year]
    type = params[:type]

    case range_type
    when "semester"
      unless year && (year.to_i > 0)
        render plain: "Invalid year", status: :bad_request
        return
      end

      year = year.to_i

      case term
      when "winter"
        start_date = DateTime.new(year, 1, 1).beginning_of_day
        end_date = DateTime.new(year, 4, 30).end_of_day
      when "summer"
        start_date = DateTime.new(year, 5, 1).beginning_of_day
        end_date = DateTime.new(year, 8, 31).end_of_day
      when "fall"
        start_date = DateTime.new(year, 9, 1).beginning_of_day
        end_date = DateTime.new(year, 12, 31).end_of_day
      else
        render plain: "Invalid term", status: :bad_request
        return
      end
    when "date_range"
      begin
        start_date = Date.parse(params[:from_date]).to_datetime.beginning_of_day
      rescue ParseError
        render plain: "Failed to parse start date"
        return
      end

      begin
        end_date = Date.parse(params[:to_date]).to_datetime.end_of_day
      rescue ParseError
        render plain: "Failed to parse end date"
        return
      end
    when "all_time"
      start_date = nil
      end_date = nil
    else
      render plain: "Invalid range type", status: :bad_request
      return
    end

    unless %w[
             visitors
             trainings
             certifications
             new_users
             training_attendees
             new_projects
             visits_by_hour
             kit_purchased
           ].include?(type)
      render plain: "Unknown report type", status: :bad_request
      return
    end

    redirect_to admin_report_generator_index_path(
                  start_date: start_date,
                  end_date: end_date,
                  report_type: type,
                  anchor: "report"
                )
  end

  def generate_spreadsheet
    start_date =
      (
        if params[:start_date].nil?
          DateTime.new(2015, 06, 01).beginning_of_day
        else
          Date.parse(params[:start_date]).to_datetime
        end
      )
    end_date =
      (
        if params[:end_date].nil?
          DateTime.now()
        else
          Date.parse(params[:end_date]).to_datetime
        end
      )
    type = params[:type]

    case type
    when "visitors"
      spreadsheet =
        ReportGenerator.generate_visitors_report(start_date, end_date)
    when "trainings"
      spreadsheet =
        ReportGenerator.generate_trainings_report(start_date, end_date)
    when "certifications"
      spreadsheet =
        ReportGenerator.generate_certifications_report(start_date, end_date)
    when "new_users"
      spreadsheet =
        ReportGenerator.generate_new_users_report(start_date, end_date)
    when "training_attendees"
      spreadsheet =
        ReportGenerator.generate_training_attendees_report(start_date, end_date)
    when "new_projects"
      spreadsheet =
        ReportGenerator.generate_new_projects_report(start_date, end_date)
    when "visits_by_hour"
      spreadsheet =
        ReportGenerator.generate_peak_hours_report(start_date, end_date)
    when "kit_purchased"
      spreadsheet =
        ReportGenerator.generate_kit_purchased_report(start_date, end_date)
    else
      render plain: "Unknown report type", status: :bad_request
      return
    end

    start_date_str = start_date.strftime("%Y-%m-%d")
    end_date_str = end_date.strftime("%Y-%m-%d")

    send_data spreadsheet.to_stream.read,
              type: "application/xlsx",
              filename:
                type + "_" + start_date_str + "_" + end_date_str + ".xlsx"
  end

  private

  def set_date_specified
    @date_specified = params[:start_date].present? && params[:end_date].present?
  end

  def new_users
    @users =
      (
        if @date_specified
          User.where(created_at: params[:start_date]..params[:end_date])
        else
          User.all
        end
      )
  end

  def certifications
    @certs =
      (
        if @date_specified
          Certification.where(
            created_at: params[:start_date]..params[:end_date]
          )
        else
          Certification.all
        end
      )
    @space_count = Hash.new
    @space_count["unknown"] = 0

    @course_count = Hash.new
    @course_count["unknown"] = 0

    @skill_count = Hash.new

    @badge_count = Hash.new

    @training_count = Hash.new

    @certs.each do |cert|
      if cert.space.present?
        if !@space_count.has_key?(cert.space.name)
          @space_count[cert.space.name] = 1
        else
          @space_count[cert.space.name] += 1
        end
      else
        @space_count["unknown"] += 1
      end

      if cert.training_session.present? &&
           cert.training_session.course_name.present?
        course_name = cert.training_session.course_name.name
        if !@course_count.has_key?(course_name)
          @course_count[course_name] = 1
        else
          @course_count[course_name] += 1
        end
      else
        @course_count["unknown"] += 1
      end

      skill_name = cert.training.skill.name
      if !@skill_count.has_key?(skill_name)
        @skill_count[skill_name] = 1
      else
        @skill_count[skill_name] += 1
      end

      training_name = cert.training.name
      if !@training_count.has_key?(training_name)
        @training_count[training_name] = 1
      else
        @training_count[training_name] += 1
      end

      cert.badges.each do |badge|
        badge_name = badge.badge_template.badge_name
        if !@badge_count.has_key?(badge_name)
          @badge_count[badge_name] = 1
        else
          @badge_count[badge_name] += 1
        end
      end
    end
  end

  def trainings
    @training_sessions =
      (
        if @date_specified
          TrainingSession.where(
            created_at: params[:start_date]..params[:end_date]
          )
        else
          TrainingSession.all
        end
      )
    @training_sessions = @training_sessions.unscope(:order)

    @space_count = Hash.new
    @space_count["unknown"] = 0

    @trainings_count = Hash.new

    @attendance_count = Hash.new

    @training_sessions.each do |training_session|
      if training_session.space.present?
        space_name = training_session.space.name
        if !@space_count.has_key?(space_name)
          @space_count[space_name] = 1
        else
          @space_count[space_name] += 1
        end
      else
        @space_count["unknown"] += 1
      end

      training_name = training_session.training.name
      if !@trainings_count.has_key?(training_name)
        @trainings_count[training_name] = 1
        @attendance_count[training_name] = training_session.users.count
      else
        @trainings_count[training_name] += 1
        @attendance_count[training_name] += training_session.users.count
      end
    end
  end

  def new_projects
    @repos =
      (
        if @date_specified
          Repository.where(created_at: params[:start_date]..params[:end_date])
        else
          Repository.all
        end
      )
    @category_count = Hash.new
    @equipment_count = Hash.new

    @repos.each do |repo|
      repo.categories.each do |category|
        if !@category_count.has_key?(category.name)
          @category_count[category.name] = 1
        else
          @category_count[category.name] += 1
        end
      end

      repo.equipments.each do |equipment|
        if !@equipment_count.has_key?(equipment.name)
          @equipment_count[equipment.name] = 1
        else
          @equipment_count[equipment.name] += 1
        end
      end
    end
  end

  def visitors
    @lab_sessions =
      (
        if @date_specified
          LabSession.where(created_at: params[:start_date]..params[:end_date])
        else
          LabSession.all
        end
      )

    @space_total_count = Hash.new
    @space_unique_count = Hash.new

    Space.all.each do |space|
      lab_session_count = space.lab_sessions
      if @date_specified
        lab_session_count =
          lab_session_count.where(
            created_at: params[:start_date]..params[:end_date]
          )
      end

      @space_total_count[space.name] = lab_session_count.count
      @space_unique_count[space.name] = lab_session_count.distinct.count(
        :user_id
      )
    end

    @identity_total_count = Hash.new
    @identity_unique_count = Hash.new

    @faculty_total_count = Hash.new
    @faculty_unique_count = Hash.new

    @lab_sessions.each do |lab_session|
      if lab_session.user.present?
        faculty = lab_session.user.faculty
        identity = lab_session.user.identity
      else
        faculty = "unknown"
        identity = "unknown"
      end

      if !@identity_total_count.has_key?(identity)
        @identity_total_count[identity] = 1
      else
        @identity_total_count[identity] += 1
      end

      if !@faculty_total_count.has_key?(faculty)
        @faculty_total_count[faculty] = 1
      else
        @faculty_total_count[faculty] += 1
      end
    end

    @lab_sessions
      .pluck(:user_id)
      .uniq
      .each do |user_id|
        user = User.find_by(id: user_id)

        unless user.nil?
          faculty = user.faculty
          identity = user.identity

          if !@identity_unique_count.has_key?(identity)
            @identity_unique_count[identity] = 1
          else
            @identity_unique_count[identity] += 1
          end

          if !@faculty_unique_count.has_key?(faculty)
            @faculty_unique_count[faculty] = 1
          else
            @faculty_unique_count[faculty] += 1
          end
        end
      end
  end
end
