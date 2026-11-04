# frozen_string_literal: true

# The domain half of a student-card tap: look the card up, create the temporary
# card when it is unknown, and toggle the owner's lab session. Shared by
# RfidController#card_number (Pi readers and the legacy React app) and
# Api::V1::RfidTapsController (phone NFC tap). The callers authenticate, rate
# limit, resolve the space and render; this object never touches the request.
class RfidTap
  # outcome: :sign_in / :sign_out (card linked, session toggled), :unlinked_card
  # (known card with no owner yet), :new_card (unknown card stored), :invalid_card
  # (blank card number, nothing stored).
  Result = Struct.new(:outcome) do
    def success_message
      { sign_in: "RFID sign in", sign_out: "RFID sign out" }[outcome]
    end

    def signed? = success_message.present?
  end

  def self.call(...) = new(...).call

  # card: the card number as sent (may be nil); space: the resolved Space;
  # mac_address: the reader's MAC, nil for a phone tap; tap_start: for the
  # elapsed-ms trace.
  def initialize(card:, space:, mac_address:, tap_start: Time.current)
    @card = card
    @space = space
    @space_id = space.id
    @mac_address = mac_address
    @tap_start = tap_start
  end

  def call
    rfid, created = Rfid.find_or_create_card(@card, mac_address: @mac_address)
    unless rfid.persisted?
      TapBoxLog.log_invalid_rfid(card_number: @card, mac_address: @mac_address, errors: rfid.errors.full_messages)
      return Result.new(:invalid_card)
    end

    if created
      TapBoxLog.log_new_unknown_card(card_number: @card, space: @space, mac_address: @mac_address)
      return Result.new(:new_card)
    end

    # Unowned card: remember the reader and move it to the top of the unlinked list.
    # The update only matches while the card is still unowned; if a staff link got
    # in first it is a tap of a linked card after all.
    if rfid.user_id.nil? &&
       Rfid.where(id: rfid.id, user_id: nil).update_all(mac_address: @mac_address, updated_at: Time.current).zero?
      rfid.reload
    end

    if rfid.user_id
      # User has a card associated with their account
      user = rfid.user
      elapsed_ms = ((Time.current - @tap_start) * 1000).round(1)
      TapBoxLog.log_card_recognized(user: user, card_number: @card, space: @space, mac_address: @mac_address, elapsed_ms: elapsed_ms)
      check_session(rfid)
    else
      TapBoxLog.log_unlinked_card(card_number: @card, space: @space, mac_address: @mac_address)
      Result.new(:unlinked_card)
    end
  end

  private

  def check_session(rfid)
    active_sessions = rfid.user.lab_sessions.active

    if active_sessions.present?
      # Sign out of all spaces
      active_sessions.sign_out_session
      # If user tapped somewhere other than last active space, make a new
      # session.
      last_active_location = active_sessions.last.space_id

      if last_active_location != @space_id
        previous_space = Space.find_by(id: last_active_location)
        TapBoxLog.log_sign_out(user: rfid.user, card_number: rfid.card_number, space: @space, mac_address: @mac_address, previous_space: previous_space)
        new_session(rfid)
      else
        TapBoxLog.log_sign_out(user: rfid.user, card_number: rfid.card_number, space: @space, mac_address: @mac_address)
        StaffDashboardChannel.send_tap_out rfid.user, @space_id
        Result.new(:sign_out)
      end
    else
      result = new_session(rfid)
      TapBoxLog.log_membership_check_queued(user: rfid.user, card_number: rfid.card_number, space: @space, mac_address: @mac_address)
      CardTapJob.perform_later(rfid, @space_id)
      result
    end
  end

  def new_session(rfid)
    LabSession.create_session(user: rfid.user, mac_address: @mac_address, space_id: @space_id)
    TapBoxLog.log_sign_in(user: rfid.user, card_number: rfid.card_number, space: @space, mac_address: @mac_address)
    Result.new(:sign_in)
  end
end
