# frozen_string_literal: true

# SQL dumps into csv for CDEL
class CdelReportGenerator
  def self.generate_visitors_report(start_date, end_date)
    headers = user_headers + %i[spaces.name sign_in_time sign_out_time]
    query =
      LabSession
        .where(created_at: start_date..end_date)
        .joins(:user, :space)
        .pluck(*headers)
    make_into_csv headers, query
  end

  def self.generate_certifications_report(start_date, end_date)
    headers =
      user_headers +
        %i[
          spaces.name
          training_sessions.course
          training_sessions.level
          trainings.name
          skills.name
        ]
    query =
      Certification
        .where(created_at: start_date..end_date)
        .joins(:user, :training_session, { training: :skill }, :space)
        .pluck(*headers)
    make_into_csv headers, query
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
