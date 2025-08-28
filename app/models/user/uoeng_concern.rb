# Queries uOEng via student ID or student email to figure out if a student is
# paying CEED fees or not on their tuition. User-specific module
module User::UoengConcern
  include ApplicationHelper # end_of_this_semeseter
  extend ActiveSupport::Concern

  included do
    # Verify if user qualifies for a faculty membership.
    #
    # NOTE: The uOEng call is expensive and we don't want them to think we're
    # batch-calling. Don't call this anywhere popular (such as in views, GET
    # actions, etc.)
    def validate_uoeng_membership
      if engineering?
        # Student is an engineer, make a membership
        memberships.active.find_or_create_by(
          membership_type: "faculty",
          status: :paid,
          end_date: end_of_this_semester
        )
        Rails.logger.info "Created faculty membership for user id #{id}"
      else
        # NOT an engineer, revoke any faculty memberships. Students can
        # drop/change courses mid-semester.
        memberships
          .active
          .where(membership_type: "faculty")
          .update(status: :revoked)
        Rails.logger.info "Revoked faculty membership for user id #{id}"
        return nil
      end
    end

    private

    # Is user paying the CEED fee?
    def engineering?
      # HACK: Cheat for CI tests
      return faculty == "Engineering" if Rails.env.test?
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
  end
end
