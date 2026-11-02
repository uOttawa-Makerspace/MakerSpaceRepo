# frozen_string_literal: true

module Api
  module V1
    # Unlinked card taps. Contract: doc/api/v1/rfid.md.
    class RfidCardsController < BaseController
      LIMIT = 5

      before_action :require_staff!

      # Same set as RfidController#get_unset_rfids: unlinked cards last tapped on a
      # reader in the staff member's assigned space (every space's readers when none
      # is assigned), newest first, at most 5.
      def index
        unless params[:linked].to_s == "false"
          return render_error(:validation_failed, "Validation failed", status: :unprocessable_content,
                              fields: { linked: ["must be false (only unlinked cards are listed)"] })
        end

        macs = PiReader.where(space: current_user.space || Space.all).pluck(:pi_mac_address)
        cards = Rfid.recent_unset.where(mac_address: macs).first(LIMIT)
        render json: cards.map { |c| { card_number: c.card_number, tapped_at: c.updated_at.utc.iso8601 } }
      end
    end
  end
end
