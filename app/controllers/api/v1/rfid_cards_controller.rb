# frozen_string_literal: true

module Api
  module V1
    # Unlinked card taps. Contract: doc/api/v1/rfid.md.
    class RfidCardsController < BaseController
      LIMIT = 5

      before_action :require_staff!

      # Same set as RfidController#get_unset_rfids: unlinked cards last tapped on a
      # reader of the caller's current space (every space for an admin), newest first, at most 5.
      def index
        unless params[:linked].to_s == "false"
          return render_error(:validation_failed, "Validation failed", status: :unprocessable_content,
                              fields: { linked: ["must be false (only unlinked cards are listed)"] })
        end

        cards = Rfid.unlinked_for(current_user).first(LIMIT)
        render json: cards.map { |c| { card_number: c.card_number, tapped_at: c.updated_at.utc.iso8601 } }
      end
    end
  end
end
