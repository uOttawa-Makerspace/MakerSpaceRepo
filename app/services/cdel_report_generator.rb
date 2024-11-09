# frozen_string_literal: true

# SQL dumps into csv for CDEL
# The goal here is to provide what CDEL doesn't have
# CEED space visitors, lab and equipment usages, sign up times and rates
# They know student demographics and faculties, and have much more accurate data
# than we do. We don't bother reporting gender, faculty, because they can get that
# via the student email/student number
#
# This class returns the data as a CSV, and the filename
# because this is also being called by a periodic mailer
# ensures consistency across the manual admin view generator and the MsrMailer
#
# NOTE: If selecting a column make sure you specify table name to avoid duplicating rows
class CdelReportGenerator
  # Used by the mailer
  def self.generate_all_reports(start_date, end_date)
    [
      self.generate_visitors_report(start_date, end_date),
      self.generate_certifications_report(start_date, end_date),
      self.generate_new_users_report(start_date, end_date)
    ]
  end

  def self.generate_visitors_report(start_date, end_date)
    headers =
      user_headers +
        %i[spaces.name lab_sessions.sign_in_time lab_sessions.sign_out_time]
    query =
      LabSession
        .where(created_at: start_date..end_date)
        .joins(:user, :space)
        .order(:created_at)
        .pluck(*headers)
    {
      data: make_into_csv(headers, query),
      filename: "CEED_visitors_dump-#{start_date}-#{end_date}.csv"
    }
  end

  def self.generate_certifications_report(start_date, end_date)
    headers =
      user_headers +
        %i[
          spaces.name
          training_sessions.course
          training_sessions.level
          training_sessions.created_at
          trainings.name
          skills.name
        ]
    query =
      Certification
        .where(created_at: start_date..end_date)
        .joins(:user, :training_session, { training: :skill }, :space)
        .order(:created_at)
        .pluck(*headers)
    {
      data: make_into_csv(headers, query),
      filename: "CEED_certifications_dump-#{start_date}-#{end_date}.csv"
    }
  end

  def self.generate_new_users_report(start_date, end_date)
    headers =
      user_headers +
        %i[
          users.username
          users.created_at
          users.last_signed_in_time
          users.last_seen_at
          users.use
          users.how_heard_about_us
          users.confirmed
        ]
    query =
      User
        .where(created_at: start_date..end_date)
        .order(:created_at)
        .pluck(*headers)
    {
      data: make_into_csv(headers, query),
      filename:
        "CEED_new_users_dump-#{start_date.to_date}-#{end_date.to_date}.csv"
    }
  end

  private

  def self.make_into_csv(headers, query)
    CSV.generate do |csv|
      csv << headers
      query.each { |row| csv << row }
    end
  end

  def self.user_headers
    %i[
      users.id
      users.name
      users.email
      users.identity
      users.student_id
      users.program
    ]
  end
end
