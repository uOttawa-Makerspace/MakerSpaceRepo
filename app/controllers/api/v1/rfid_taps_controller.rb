# frozen_string_literal: true

module Api
  module V1
    # Phone NFC tap by staff. Contract: doc/api/v1/rfid.md. Pi readers keep using
    # the legacy device endpoint (POST /rfid/card_number with a registered MAC).
    class RfidTapsController < BaseController
      before_action :require_staff!
      # The SAME budgets as RfidController#card_number, counted under the
      # same cache keys (scope "rfid", names "tap" / "tap-ip"; keep in step with
      # RfidController): 60 taps/min per staff user and 600/min per IP, shared with
      # the legacy staff tap so a user cannot get 60 on each. After the auth filter,
      # so guests do not count.
      rate_limit to: 60, within: 1.minute, only: :create, scope: "rfid", name: "tap",
                 by: -> { "staff:#{current_user.id}" }, with: :rate_limited
      rate_limit to: 600, within: 1.minute, only: :create, scope: "rfid", name: "tap-ip",
                 by: -> { request.remote_ip }, with: :rate_limited

      def create
        tap_start = Time.current
        card = params.require(:card_number)
        return invalid(:card_number, "must be a string") unless card.is_a?(String)
        return invalid(:card_number, "is invalid") unless Rfid.valid_card_number?(card)

        raw_space = params.require(:space_id)
        return invalid(:space_id, "must be a space id") unless raw_space.is_a?(Integer) || (raw_space.is_a?(String) && raw_space.match?(/\A\d{1,18}\z/))

        space = Space.find(raw_space)
        TapBoxLog.log_card_tap(card_number: card, mac_address: nil, space_id_param: raw_space)
        result = RfidTap.call(card: card, space: space, mac_address: nil, tap_start: tap_start)
        if result.signed?
          render json: { success: result.success_message }
        else
          render_error(:card_not_linked, "This card is not linked to a user yet", status: :unprocessable_content,
                       fields: { card_number: ["is not linked to a user"] })
        end
      end

      private

      def invalid(field, message)
        render_error(:validation_failed, "Validation failed", status: :unprocessable_content, fields: { field => [message] })
      end
    end
  end
end
