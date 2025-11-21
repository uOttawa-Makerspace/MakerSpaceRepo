class Event < ApplicationRecord
  belongs_to :created_by, class_name: 'User'
  belongs_to :space
  has_many :event_assignments, dependent: :destroy
  has_many :users, through: :event_assignments, source: :user

  belongs_to :training, optional: true
  belongs_to :course_name, optional: true

  validates :start_time, :end_time, :created_by_id, :space_id, :event_type, presence: true

  validate :start_time_must_be_before_end_time
  validate :weekly_frequency_must_contain_days

  before_save :upsert_google_event
  before_destroy :delete_google_event

  private

  def start_time_must_be_before_end_time
    return unless start_time.present? && end_time.present? && start_time >= end_time
      errors.add(:start_time, "must be before the end time")
  end
  
  def weekly_frequency_must_contain_days
    if recurrence_rule.present? && recurrence_rule.include?("FREQ=WEEKLY") && !recurrence_rule.include?("BYDAY")
      errors.add(:recurrence_rule, "must include days of the week when using weekly frequency")
    end
  end
  
  # Google Calendar!
  def upsert_google_event
    return if draft
    Event.upsert_event(self)
  end

  def delete_google_event
    Event.delete_event(self) if google_event_id.present?
  end

  def self.authorizer # rubocop:disable Lint/IneffectiveAccessModifier,Metrics/AbcSize
    scope = "https://www.googleapis.com/auth/calendar"

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

  def self.upsert_event(event) # rubocop:disable Lint/IneffectiveAccessModifier,Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
    service = Google::Apis::CalendarV3::CalendarService.new
    service.authorization = authorizer
    attendees = []
    unless Rails.env.test?
      event.users.each do |user|
        attendees << Google::Apis::CalendarV3::EventAttendee.new(
          email: user.email
        )
      end
    end

          title = if event.title == event.event_type.capitalize && !event.event_assignments.empty?
            "#{event.event_type == 'training' ? "#{event.training.name} (#{event.course_name.name || ''} - #{event.language || ''})" : event.event_type.capitalize} for #{event.event_assignments.map do |ea|
 ea.user.name end.join(", ")}"
          else 
            event.title
          end

    description = event.description.to_s
    if event.event_type == 'training' && event.training_id.present?
      language = case event.language
                when 'en' then 'English'
                when 'fr' then 'French'
                else event.language.to_s
                end
      
      training_details = [
        "Training: #{event.training.name_en}",
        "Language: #{language}",
        "Course: #{event&.course_name&.name}" # Assuming there's a course association
      ].join("\n")

      description = [description, training_details].reject(&:blank?).join("\n\n")
    end

    gcal_event =
      Google::Apis::CalendarV3::Event.new(
        summary: title,
        description: description,
        start:
          Google::Apis::CalendarV3::EventDateTime.new(
            date_time: event.start_time.iso8601,
            time_zone: "America/Toronto"
          ),
        end:
          Google::Apis::CalendarV3::EventDateTime.new(
            date_time: event.end_time.iso8601,
            time_zone: "America/Toronto"
          ),
        attendees: attendees
      )

    if event.recurrence_rule.present?
      rule_lines = event.recurrence_rule.strip.lines.map(&:strip)

      recurrence_lines = rule_lines.select do |line|
        line.start_with?("RRULE:") || line.start_with?("EXDATE:")
      end

      gcal_event.recurrence = recurrence_lines if recurrence_lines.any?
    end

    calendar_id = return_space_calendar(event.space)
    if event.google_event_id.present?
      begin
        service.update_event(calendar_id, event.google_event_id, gcal_event)
      rescue Google::Apis::ClientError => e
        Rails.logger.error "Failed to update Google event #{event.id}: #{e.message}"
      end
    else
      begin
        response = service.insert_event(calendar_id, gcal_event)
        event.update(google_event_id: response.id)
      rescue StandardError => e
        Rails.logger.error "Failed to create event #{event.id}: #{e.message}"
      end
    end
  end

  def self.delete_event(event) # rubocop:disable Lint/IneffectiveAccessModifier
    service = Google::Apis::CalendarV3::CalendarService.new
    service.authorization = authorizer

    calendar_id = return_space_calendar(event.space)

    begin
      response = service.delete_event(calendar_id, event.google_event_id)
    rescue Google::Apis::ClientError => e
        Rails.logger.error "Failed to delete Google event #{event.id}: #{e.message}"
    end

    response
  end

  def self.return_space_calendar(space) # rubocop:disable Lint/IneffectiveAccessModifier
    if space.name == "MTC"
      "c_f6jqt6dcoj7iovfa88a52nh9c4@group.calendar.google.com" # MTC
    elsif space.name == "Makerspace"
      "c_g1bk6ctpenjeko2dourrr0h6pc@group.calendar.google.com" # Makerspace
    else
      "c_hbktsseobsqd92u5rufsjbcok8@group.calendar.google.com" # Test Calendar
    end
  end
end