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
      ["Kit purchased", :kit_purchased],
      ["Popular Hours", :popular_hours]
    ]

    @report_parameter = %w[
      certifications
      new_projects
      new_users
      trainings
      training_attendees
      visitors
      visits_by_hour
      kit_purchased
      popular_hours
    ]

    return unless params[:report_type].present?
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
        training_attendees
      when "new_projects"
        new_projects
      when "visits_by_hour"
        visits_by_hour
      when "kit_purchased"
        kit_purchased
      when "popular_hours"
        popular_hours
      else
        render plain: "Unknown report type", status: :bad_request
        nil
      end
    
  end

  # generate report as an html graph
  # This is a button on the page btw
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
             popular_hours
           ].include?(type)
      render plain: "Unknown report type", status: :bad_request
      return
    end

    # reload page but with GET params
    # the index template renders parameters if present
    redirect_to admin_report_generator_index_path(
                  start_date: start_date,
                  end_date: end_date,
                  report_type: type,
                  anchor: "report",
                  range_type: range_type, # save selection params
                  term: term, # Semester params
                  year: year
                ),
                notice: "Successfully generated #{type.gsub("_", " ")} report"
  end

  def generate_spreadsheet
    start_date =
      (
        if params[:start_date].nil?
          DateTime.new(2015, 0o6, 0o1).beginning_of_day
        else
          Date.parse(params[:start_date]).to_datetime
        end
      )
    end_date =
      (
        if params[:end_date].nil?
          DateTime.now
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

  # Each function below corresponds to a report type
  # We collect the data in the controller

  def set_date_specified
    @date_specified = params[:start_date].present? && params[:end_date].present?
  end

  def new_users
    @users =
      (
        if @date_specified
          # params gives everything as space
          # passing this as a string CHANGES the result
          ReportGenerator.get_new_users(
            params[:start_date].to_date,
            params[:end_date].to_date
          )
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
        .includes(:badges)
        .includes(badges: :badge_template)
        .includes(:space)
        .includes(training_session: %i[course_name training])
        .includes(training: [:skill])
    @space_count = {}
    @space_count["unknown"] = 0

    @course_count = {}
    @course_count["unknown"] = 0

    @skill_count = {}

    @badge_count = {}

    @training_count = {}

    # For each certification in our database
    @certs.each do |cert|
      if cert.space.present?
        # Go through each cert, count number of distinct certifying spaces
        # Because CEED has a bunch of spaces that aren't what we want
        if !@space_count.has_key?(cert.space.name)
          @space_count[cert.space.name] = 1
        else
          @space_count[cert.space.name] += 1
        end
      else
        @space_count["unknown"] += 1
      end

      # get said cert's training session
      if cert.training_session.present? &&
           cert.training_session.course_name.present?
        course_name = cert.training_session.course_name.name
        # count certifying courses too
        if !@course_count.has_key?(course_name)
          @course_count[course_name] = 1
        else
          @course_count[course_name] += 1
        end
      else
        # some don't have courses (open to public)
        @course_count["unknown"] += 1
      end

      # Count by skill and name
      skill_name = cert.training.skill.name
      if !@skill_count.has_key?(skill_name)
        @skill_count[skill_name] = 1
      else
        @skill_count[skill_name] += 1
      end

      # get cert training topic (?)
      training_name = cert.training.name_en
      if !@training_count.has_key?(training_name)
        @training_count[training_name] = 1
      else
        @training_count[training_name] += 1
      end

      # number of badges handed out
      cert.badges.each do |badge|
        badge_name = badge.badge_template.localized_name
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
      ).includes(:training, :space, :user)

    @training_sessions = @training_sessions.unscope(:order)

    @space_count = {}
    @space_count["unknown"] = 0

    @trainings_count = {}

    @attendance_count = {}

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

      training_name = training_session.training.name_en
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
    @category_count = {}
    @equipment_count = {}

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
      ).includes(:user)

    @space_total_count = {}
    @space_unique_count = {}

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

    @identity_total_count = {}
    @identity_unique_count = {}

    @faculty_total_count = {}
    @faculty_unique_count = {}

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

    all_users = @lab_sessions.pluck(:user_id).uniq
    User
      .where(id: all_users)
      .each do |user|
        next if user.nil?
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
    @identity_total_count = @identity_total_count.transform_keys(&:humanize)
    @identity_unique_count = @identity_unique_count.transform_keys(&:humanize)
  end

  def visits_by_hour
    @lab_hash = {}

    lab_sessions =
      (
        if @date_specified
          LabSession.where(created_at: params[:start_date]..params[:end_date])
        else
          LabSession.all
        end
      )
    @spaces = Space.all.order(name: :asc)

    @lab_hash["all"] = lab_sessions

    Space.all.each do |space|
      sessions = if @date_specified
        space.lab_sessions.where(
            created_at: params[:start_date]..params[:end_date]
          )
      else
        space.lab_sessions
                 end

      @lab_hash[space.name.gsub(" ", "-")] = sessions
    end
  end

  def kit_purchased
    @project_kits =
      (
        if @date_specified
          ProjectKit.where(created_at: params[:start_date]..params[:end_date])
        else
          ProjectKit.all
        end
      )

    @pp_hash = {}

    @project_kits.each do |pk|
      pp_name = pk.proficient_project.title
      if !@pp_hash.has_key?(pp_name)
        @pp_hash[pp_name] = 1
      else
        @pp_hash[pp_name] += 1
      end
    end
  end

  def training_attendees
    @training_sessions =
      (
        if @date_specified
          TrainingSession.where(
            created_at: params[:start_date]..params[:end_date]
          )
        else
          TrainingSession.all
        end
      ).includes(:users, :user, :trainings)
    @spaces = Space.order(name: :asc).includes(:certifications)

    total_certs = {}
    total_sessions = {}
    @monthly_average = {}

    (1..12).each do |m|
      month_name = Date::MONTHNAMES[m]
      total_certs[month_name] = 0
      total_sessions[month_name] = 0
    end

    if @date_specified
      (params[:start_date].to_datetime..params[:end_date].to_datetime)
        .select { |date| date.day == 1 }
        .map do |date|
          month_name = date.end_of_month.strftime("%B")
          certs =
            Certification.where(
              created_at: date.beginning_of_month..date.end_of_month
            )
          total_certs[month_name] += certs.count
          total_sessions[month_name] += certs
            .pluck(:training_session_id)
            .uniq
            .count
        end
    else
      (DateTime.new(2015, 0o6, 0o1).beginning_of_day..DateTime.now)
        .select { |date| date.day == 1 }
        .map do |date|
          month_name = date.end_of_month.strftime("%B")
          certs =
            Certification.where(
              created_at: date.beginning_of_month..date.end_of_month
            )
          total_certs[month_name] += certs.count
          total_sessions[month_name] += certs
            .pluck(:training_session_id)
            .uniq
            .count
        end
    end

    (1..12).each do |m|
      month_name = Date::MONTHNAMES[m]
      if total_certs[month_name] != 0
        @monthly_average[month_name] = total_certs[month_name].to_f /
          total_sessions[month_name]
      end
    end
  end

  def popular_hours
    @space = @user.lab_sessions&.last&.space || Space.first
    @spaces = Space.all.order(name: :asc)
    @weekdays = Date::DAYNAMES

    return unless @date_specified
      @info =
        PopularHour.popular_hours_per_period(
          params[:start_date].to_date,
          params[:end_date].to_date
        )
      params[:report_type] = "popular_hours_per_period"
    
  end
end
