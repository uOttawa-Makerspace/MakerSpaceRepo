# frozen_string_literal: true

# Some notes for later reports: If filtering for a specific type of day, such as
# on sundays only or saturdays only, use .select(&:sunday?).map(&:all_day). The
# column type for created_at includes times all_day converts the result from a
# single point in time to a range for the where query to properly function.
#
# Prefer to enable strict_loading on any query you do here, these reports pull a
# lot of data and reducing round trips is important.

class Admin::ReportGeneratorController < AdminAreaController
  layout 'admin_area'
  require 'date'

  rescue_from ReportPeriod::Invalid do |error|
    render plain: error.message, status: :bad_request
  end

  def index
    @report_types = [
      ['Certifications', :certifications],
      ['New Projects', :new_projects],
      ['New Users', :new_users],
      ['Trainings', :trainings],
      ['Training Attendees', :training_attendees],
      ['Visitors', :visitors],
      ['Visits by Hour', :visits_by_hour],
      ['Kit purchased', :kit_purchased],
      ['Popular Hours', :popular_hours],
      ['Frequent Visitors', :frequent_visitors]
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
      frequent_visitors
    ]

    return unless params[:report_type].present?
    set_date_specified

    case params[:report_type]
    when 'visitors'
      visitors
    when 'trainings'
      trainings
    when 'certifications'
      certifications
    when 'new_users'
      new_users
    when 'training_attendees'
      training_attendees
    when 'new_projects'
      new_projects
    when 'visits_by_hour'
      visits_by_hour
    when 'kit_purchased'
      kit_purchased
    when 'popular_hours'
      popular_hours
    when 'frequent_visitors'
      frequent_visitors
    else
      render plain: 'Unknown report type', status: :bad_request
      nil
    end
  end

  # generate report as an html graph
  # This is a button on the page btw
  def generate
    period = chosen_period
    type = params[:type]

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
             frequent_visitors
           ].include?(type)
      render plain: 'Unknown report type', status: :bad_request
      return
    end

    # reload page but with GET params: the picked days, which the index and
    # the spreadsheet both read as whole days in the application time zone
    # the index template renders parameters if present
    redirect_to admin_report_generator_index_path(
                  start_date: period&.first_day,
                  end_date: period&.last_day,
                  report_type: type,
                  anchor: 'report',
                  range_type: params[:range_type], # save selection params
                  term: params[:term], # Semester params
                  year: params[:year]
                ),
                notice: "Successfully generated #{type.gsub('_', ' ')} report"
  end

  def generate_spreadsheet
    start_date, end_date = spreadsheet_window
    type = params[:type]

    case type
    when 'visitors'
      spreadsheet =
        ReportGenerator.generate_visitors_report(start_date, end_date)
    when 'trainings'
      spreadsheet =
        ReportGenerator.generate_trainings_report(start_date, end_date)
    when 'certifications'
      spreadsheet =
        ReportGenerator.generate_certifications_report(start_date, end_date)
    when 'new_users'
      spreadsheet =
        ReportGenerator.generate_new_users_report(start_date, end_date)
    when 'training_attendees'
      spreadsheet =
        ReportGenerator.generate_training_attendees_report(start_date, end_date)
    when 'new_projects'
      spreadsheet =
        ReportGenerator.generate_new_projects_report(start_date, end_date)
    when 'visits_by_hour'
      spreadsheet =
        ReportGenerator.generate_peak_hours_report(start_date, end_date)
    when 'kit_purchased'
      spreadsheet =
        ReportGenerator.generate_kit_purchased_report(start_date, end_date)
    else
      render plain: 'Unknown report type', status: :bad_request
      return
    end

    start_date_str = start_date.strftime('%Y-%m-%d')
    end_date_str = end_date.strftime('%Y-%m-%d')

    send_data spreadsheet.to_stream.read,
              type: 'application/xlsx',
              filename:
                type + '_' + start_date_str + '_' + end_date_str + '.xlsx'
  end

  private

  # From the start of the first day to the end of the last. Without a first day
  # the report starts on 1 June 2015, and without a last day it ends now.
  def spreadsheet_window
    period =
      ReportPeriod.parse(
        params[:start_date] || '2015-06-01',
        params[:end_date] || Date.current.to_s
      )
    window = period.window
    [window.begin, params[:end_date].nil? ? Time.current : window.end]
  end

  # The period of the chosen range type; nil for all time.
  def chosen_period
    case params[:range_type]
    when 'semester'
      ReportPeriod.semester(params[:term], params[:year])
    when 'date_range'
      ReportPeriod.parse(params[:from_date], params[:to_date])
    when 'all_time'
      nil
    else
      raise ReportPeriod::Invalid, 'Invalid range type'
    end
  end

  # Each function below corresponds to a report type
  # We collect the data in the controller

  # Without picked days the report covers all time.
  def set_date_specified
    @date_specified = params[:start_date].present? && params[:end_date].present?
    @period =
      (ReportPeriod.parse(params[:start_date], params[:end_date]) if @date_specified)
    @report_window = @period ? @period.window : (nil..nil)
  end

  def new_users
    @users =
      (
        if @date_specified
          ReportGenerator.get_new_users(@report_window.begin, @report_window.end)
        else
          User.including_deleted
        end
      )
  end

  def certifications
    @certs =
      (
        if @date_specified
          Certification.where(
            created_at: @report_window
          )
        else
          Certification.all
        end
      )
        .includes(:space)
        .includes(training_session: [:course_name, { training: :skill }])
    @space_count = {}
    @space_count['unknown'] = 0

    @course_count = {}
    @course_count['unknown'] = 0

    @skill_count = {}

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
        @space_count['unknown'] += 1
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
        @course_count['unknown'] += 1
      end

      # Count by skill and name
      skill_name = cert.training_session.training.skill.name
      if !@skill_count.has_key?(skill_name)
        @skill_count[skill_name] = 1
      else
        @skill_count[skill_name] += 1
      end

      # get cert training topic (?)
      training_name = cert.training_session.training.name_en
      if !@training_count.has_key?(training_name)
        @training_count[training_name] = 1
      else
        @training_count[training_name] += 1
      end
    end
  end

  def trainings
    @training_sessions =
      (
        if @date_specified
          TrainingSession.where(
            created_at: @report_window
          )
        else
          TrainingSession.all
        end
      ).includes(:training, :space)

    @training_sessions = @training_sessions.unscope(:order)

    @space_count = {}
    @space_count['unknown'] = 0

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
        @space_count['unknown'] += 1
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
          Repository.where(created_at: @report_window)
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
          LabSession.where(created_at: @report_window)
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
            created_at: @report_window
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
        faculty = 'unknown'
        identity = 'unknown'
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
      .including_deleted
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
          LabSession.where(created_at: @report_window)
        else
          LabSession.all
        end
      )
    @spaces = Space.all.order(name: :asc)

    @lab_hash['all'] = lab_sessions

    Space.all.each do |space|
      sessions =
        if @date_specified
          space.lab_sessions.where(
            created_at: @report_window
          )
        else
          space.lab_sessions
        end

      @lab_hash[space.name.gsub(' ', '-')] = sessions
    end
  end

  def kit_purchased
    @project_kits =
      (
        if @date_specified
          ProjectKit.where(created_at: @report_window)
        else
          ProjectKit.all
        end
      ).includes(:proficient_project, :user)

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
            created_at: @report_window
          )
        else
          TrainingSession.all
        end
      )
    @spaces = Space.order(name: :asc)

    @monthly_average = monthly_attendee_averages(report_days)
  end

  # Every day of the report: the picked days, else 2015-06-01 to today.
  def report_days
    if @date_specified
      return @report_window.begin.to_date..@report_window.end.to_date
    end

    Date.new(2015, 6, 1)..Date.current
  end

  # Certificates per training session for each month that starts within the
  # days and has certificates, the whole month in the application time zone,
  # named with its year ("March 2026").
  def monthly_attendee_averages(days)
    months = days.select { |day| day.day == 1 }
    months.each_with_object({}) do |month, averages|
      certs = Certification.where(created_at: month.in_time_zone.all_month)
      count = certs.count
      next if count.zero?

      sessions = certs.pluck(:training_session_id).uniq.count
      averages[month.strftime('%B %Y')] = count.to_f / sessions
    end
  end

  def popular_hours
    @space = @user.lab_sessions&.last&.space || Space.first
    @spaces = Space.all.order(name: :asc)
    @weekdays = Date::DAYNAMES

    return unless @date_specified
    @info =
      PopularHour.popular_hours_per_period(
        @period.first_day,
        @period.last_day
      )
  end

  # Without picked days the visits of all time are counted, and the list of
  # weekend days is left out.
  def frequent_visitors
    @weekends = weekend_days
    @lab_sessions =
      Space.all.map do |space|
        [
          space.name,
          # Full weeks
          LabSession
            .strict_loading
            .joins(:user)
            .where(
              created_at: @report_window,
              space: space
            )
            .group(:user)
            .order('count(users.id) desc')
            .limit(20)
            .count,
          # Weekend only, by the weekday in the application time zone
          LabSession
            .strict_loading
            .joins(:user)
            .where(created_at: @report_window, space: space)
            .where(
              "EXTRACT(DOW FROM (lab_sessions.created_at AT TIME ZONE 'UTC') AT TIME ZONE ?) IN (0, 6)",
              Time.zone.tzinfo.name
            )
            .group(:user)
            .order('count(users.id) desc')
            .limit(20)
            .count
        ]
      end
  end

  def weekend_days
    return unless @period

    (@period.first_day..@period.last_day).select do |day|
      day.saturday? || day.sunday?
    end
  end
end
