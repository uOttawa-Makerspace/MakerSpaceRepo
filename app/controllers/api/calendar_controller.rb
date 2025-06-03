class Api::CalendarController < ApplicationController
  skip_before_action :verify_authenticity_token

  def sync_to_google
    service = Google::Apis::CalendarV3::CalendarService.new
    service.authorization = authorize_google_service

    calendar_id = "c_hbktsseobsqd92u5rufsjbcok8@group.calendar.google.com"

    events = Event.includes(event_assignments: :user).where("draft = false AND start_time >= ?", 
Time.now.beginning_of_day.utc)

    created_count = 0
    updated_count = 0
    failed = []

    events.each do |event|
      assigned_names = event.event_assignments.map { |ea| ea.user.name }.join(", ")

      
      title = if event.title == event.event_type.capitalize && !event.event_assignments.empty?
        "#{event.event_type.capitalize} for #{assigned_names}"
      else 
        event.title
      end

      gcal_event = Google::Apis::CalendarV3::Event.new(
        summary: title,
        description: [event.description, "Assigned: #{assigned_names}"].compact.join("\n\n"),
        start: {
          date_time: event.start_time.iso8601,
          time_zone: "America/Toronto"
        },
        end: {
          date_time: event.end_time.iso8601,
          time_zone: "America/Toronto"
        }
      )

      if event.recurrence_rule.present?
        rule_lines = event.recurrence_rule.strip.lines.map(&:strip)

        recurrence_lines = rule_lines.select do |line|
          line.start_with?("RRULE:") || line.start_with?("EXDATE:")
        end

        gcal_event.recurrence = recurrence_lines if recurrence_lines.any?
      end

      if event.google_event_id.present?
        begin
          service.update_event(calendar_id, event.google_event_id, gcal_event)
          updated_count += 1
        rescue Google::Apis::ClientError => e
          Rails.logger.error "Failed to update Google event #{event.id}: #{e.message}"
          failed << { id: event.id, error: e.message }
        end
      else
        begin
          response = service.insert_event(calendar_id, gcal_event)
          event.update(google_event_id: response.id)
          created_count += 1
        rescue StandardError => e
          Rails.logger.error "Failed to create event #{event.id}: #{e.message}"
          failed << { id: event.id, error: e.message }
        end
      end
    end

    render json: { created: created_count, updated: updated_count, failed: failed }, status: :ok
  end

  private

  def authorize_google_service
    scope = ["https://www.googleapis.com/auth/calendar"]
    
    @config = {
      private_key:
        Rails.application.credentials[Rails.env.to_sym][:google][:private_key],
      client_email:
        Rails.application.credentials[Rails.env.to_sym][:google][:client_email],
      project_id:
        Rails.application.credentials[Rails.env.to_sym][:google][:project_id],
      private_key_id:
        Rails.application.credentials[Rails.env.to_sym][:google][
          :private_key_id
        ],
      type: Rails.application.credentials[Rails.env.to_sym][:google][:type]
    }

    authorizer =
      Google::Auth::ServiceAccountCredentials.make_creds(
        json_key_io: StringIO.new(@config.to_json, "r"),
        scope: scope
      )

    authorizer.sub = "volunteer@makerepo.com"    
    authorizer.fetch_access_token!
    authorizer
  end
end
