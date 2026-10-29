# frozen_string_literal: true

module Api
  module V1
    # Link / unlink a user's card. Contract: doc/api/v1/rfid.md.
    class UserRfidsController < BaseController
      before_action :require_staff!

      # The card must already have been tapped (it exists as an unlinked Rfid).
      # Refused, with nothing changed: a card another user holds, or a user who
      # already holds a different card (unlink it first). Linking the same pair
      # again is a no-op.
      def update
        card_number = params.require(:card_number)
        return invalid_card("must be a string") unless card_number.is_a?(String)

        user = find_user!
        error = nil
        Rfid.transaction do
          # Lock order: user, then card.
          User.where(id: user.id).lock("FOR NO KEY UPDATE").take
          rfid = Rfid.lock("FOR NO KEY UPDATE").find_by!(card_number: card_number)
          if rfid.user_id == user.id
            # already linked to this user
          elsif rfid.user_id.present?
            error = "is already linked to another user"
          elsif Rfid.where(user_id: user.id).exists?
            error = "user already has a card; unlink it first"
          else
            rfid.update!(user_id: user.id)
          end
        end
        return invalid_card(error) if error

        head :no_content
      end

      # Unlinks every card the user holds (normally one) and re-homes it exactly
      # as the legacy unlink_rfid does: its mac_address becomes the first reader of
      # the space of the STAFF member's last lab session, so it shows up in their
      # unlinked list. No card is a no-op.
      def destroy
        user = find_user!
        Rfid.transaction do
          User.where(id: user.id).lock("FOR NO KEY UPDATE").take
          reader = current_user.location != "no sign in yet" && Space.find_by(name: current_user.location)&.pi_readers&.first
          Rfid.where(user_id: user.id).lock("FOR NO KEY UPDATE").each do |rfid|
            rfid.user_id = nil
            rfid.mac_address = reader.pi_mac_address if reader
            rfid.save!
          end
        end
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
