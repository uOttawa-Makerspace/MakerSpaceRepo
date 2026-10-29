# frozen_string_literal: true

module Api
  module V1
    # Contract: doc/api/v1/shifts.md. The staff app's Shifts calendar: published
    # Events of type "shift" (the Shift model/table is retired; this data lives in
    # events, which the admin calendar still creates).
    class ShiftsController < BaseController
      MAX_RANGE = 100.days

      before_action :require_staff!

      def index
        space = Space.find(params[:id])
        errors = {}
        from = parse_time(:start, errors)
        to = parse_time(:end, errors)
        user_id = parse_user_id(errors)
        if from && to
          if to < from
            errors[:end] = ["must not be before start"]
          elsif to - from > MAX_RANGE
            errors[:end] = ["range must be at most #{MAX_RANGE.in_days.to_i} days"]
          end
        end
        return render_error(:validation_failed, "Validation failed", status: :unprocessable_content, fields: errors) if errors.any?

        render json: ShiftEventSerializer.call(space: space, from: from, to: to, user_id: user_id)
      end

      private

      def parse_time(key, errors)
        raw = params[key]
        (errors[key] = ["is required"]; return nil) if raw.blank?
        (errors[key] = ["must be an ISO 8601 date-time"]; return nil) unless raw.is_a?(String)

        Time.iso8601(raw).in_time_zone
      rescue ArgumentError
        errors[key] = ["must be an ISO 8601 date-time"]
        nil
      end

      def parse_user_id(errors)
        raw = params[:user_id]
        return nil if raw.nil? || (raw.is_a?(String) && raw.empty?)

        if raw.is_a?(String) && raw.match?(/\A\d{1,18}\z/)
          raw.to_i
        else
          errors[:user_id] = ["must be a user id"]
          nil
        end
      end
    end
  end
end
