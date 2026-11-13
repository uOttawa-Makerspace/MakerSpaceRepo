# frozen_string_literal: true

module Api
  module V1
    # Contract: doc/api/v1/shifts.md. The staff app's Shifts calendar: published
    # Events of type "shift" (the Shift model/table is retired; this data lives in
    # events, which the admin calendar still creates).
    class ShiftsController < BaseController
      before_action :require_staff!

      def index
        space = Space.find(params[:id])
        return if refuse_unworkable_space(space)

        errors = {}
        from = parse_time(:start, errors)
        to = parse_time(:end, errors)
        user_id = parse_user_id(errors)
        range_problem = range_error(from, to)
        errors[:end] = range_problem if range_problem
        return render_error(:validation_failed, "Validation failed", status: :unprocessable_content, fields: errors) if errors.any?

        result = ShiftEventSerializer.result(space: space, from: from, to: to, user_id: user_id)
        response.set_header("X-Truncated", "true") if result.truncated
        render json: result.items
      end

      private

      def range_error(from, to)
        return unless from && to
        return ["must not be before start"] if to < from

        ["range must be at most #{Event::MAX_FEED_RANGE.in_days.to_i} days"] if Event.feed_range_too_long?(from, to)
      end

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
