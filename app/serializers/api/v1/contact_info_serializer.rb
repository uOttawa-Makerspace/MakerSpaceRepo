# frozen_string_literal: true

module Api
  module V1
    # A contact with its opening-hour periods. Explicit allowlist (no url, space_id, ids).
    module ContactInfoSerializer
      DAYS = %w[sunday monday tuesday wednesday thursday friday saturday].freeze

      module_function

      def call(contact)
        {
          name: contact.name,
          email: contact.email,
          address: contact.address,
          phone_number: contact.phone_number,
          opening_hours: contact.opening_hours.reject(&:hidden_closed_all_week?).map { |h| opening_hour(h) }
        }
      end

      def opening_hour(hour)
        {
          target_en: hour.target_en,
          target_fr: hour.target_fr,
          notes_en: hour.notes_en,
          notes_fr: hour.notes_fr,
          closed_all_week: hour.closed_all_week == "closed",
          days: DAYS.index_with { |day| day_hours(hour, day) }
        }
      end

      # status: open | closed | hidden (the admin form's "closed all day?" select).
      def day_hours(hour, day)
        {
          status: hour.public_send("#{day}_closed_all_day"),
          opening: hour.public_send("#{day}_opening")&.strftime("%H:%M"),
          closing: hour.public_send("#{day}_closing")&.strftime("%H:%M")
        }
      end
    end
  end
end
