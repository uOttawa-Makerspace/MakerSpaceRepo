# Queries uOEng via student ID or student email to figure out if a student is
# paying CEED fees or not on their tuition
module UoengConcern
  extend ActiveSupport::Concern

  included do
    # Query and parse user details
    def uoeng_details
      # Check if we have valid data. Either query by student ID, or uOttawa
      # email
      creds = Rails.application.credentials[Rails.env.to_sym][:uoeng]
      url =
        if student_id.present?
          "#{creds[:query_by_id]}#{student_id}"
        elsif email.ends_with? "@uottawa.ca"
          "#{creds[:query_by_email]}#{email}"
        else
          # No valid query params, early out.
          return false
        end

      JSON.parse(
        Excon.get(
          url,
          headers: {
            Authorization: "Bearer #{creds[:student_information_key]}"
          }
        ).body
      )
    end

    # Is user paying the CEED fee?
    def engineering?
      # Check if we have valid data. Either query by student ID, or uOttawa
      details = uoeng_details

      # Either a fulltime engineering student, or enrolled in a CEED managed
      # course. Note the array intersection to detect courses
      (
        details["student_this_semester"] && details["fulltime"] == true &&
          details["faculty"] == "GENIE"
      ) || (details.courses_enrolled & CourseName.pluck(:name)).present?
    rescue StandardError => e
      # For now return false on all errors
      Rails.logger.fatal e
      false
    end
  end
end
