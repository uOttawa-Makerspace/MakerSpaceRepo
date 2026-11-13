# frozen_string_literal: true

module Api
  module V1
    # Link / unlink a user's card. Contract: doc/api/v1/rfid.md.
    class UserRfidsController < BaseController
      before_action :require_staff!

      # Links the card to the user. A card no reader ever saw is created (the staff
      # app scans new cards on the phone). Refused, with nothing changed: a card
      # another user holds, or a user who already holds a different card (unlink it
      # first). Linking the same pair again is a no-op.
      def update
        card_number = params.require(:card_number)
        return invalid_card("must be a string") unless card_number.is_a?(String)
        return invalid_card("is invalid") unless Rfid.valid_card_number?(card_number)

        error = Rfid.link_to_user!(card_number, find_user!)
        return invalid_card(error) if error

        head :no_content
      end

      # Unlinks every card the user holds (normally one) through
      # Rfid.unlink_from_user!: its mac_address becomes the first reader of the
      # caller's assigned space, so it shows up in their unlinked list. No card is
      # a no-op.
      def destroy
        Rfid.unlink_from_user!(find_user!, actor: current_user)
        head :no_content
      end

      private

      def invalid_card(message)
        render_error(:validation_failed, "Validation failed", status: :unprocessable_content,
                     fields: { card_number: [message] })
      end

      def find_user!
        raise ActiveRecord::RecordNotFound unless params[:id].to_s.match?(/\A\d+\z/)

        User.find(params[:id])
      end
    end
  end
end
