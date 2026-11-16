# frozen_string_literal: true

# The domain half of a student-card tap: look the card up, create the temporary
# card when it is unknown, and toggle the owner's lab session. Shared by
# RfidController#card_number (Pi readers and the legacy React app) and
# Api::V1::RfidTapsController (phone NFC tap). The callers authenticate, rate
# limit, resolve the space and render; this object never touches the request.
class RfidTap
  # A second tap of the same card in the same space this soon after the session
  # started is ignored (answered as already signed in) rather than signing out.
  REPEAT_WINDOW = 60.seconds

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

  # What one toggle did, for the work that happens after it commits: outcome is
  # :sign_in, :sign_out or :repeat (a repeat tap, nothing changed);
  # left_space_ids / previous_space_id describe a space switch.
  Toggle = Struct.new(:outcome, :left_space_ids, :previous_space_id)

  # The user row is locked for the toggle, so two taps of one user (two readers,
  # a double tap) run one after the other and the second sees the first's session.
  # Logs, broadcasts and the membership job run after the transaction commits.
  def check_session(rfid)
    toggle = User.transaction do
      rfid.user.lock!
      toggle_session(rfid.user)
    end
    finish_toggle(rfid, toggle)
  end

  def toggle_session(user)
    active_sessions = user.lab_sessions.active
    newest = active_sessions.last

    if newest.nil?
      open_session(user)
      Toggle.new(:sign_in, [], nil)
    elsif newest.space_id != @space_id
      # Sign out of all spaces and sign in here together: a failure leaves
      # the user signed in where they were.
      left_space_ids = active_sessions.pluck(:space_id).uniq - [@space_id]
      active_sessions.sign_out_session
      open_session(user)
      Toggle.new(:sign_in, left_space_ids, newest.space_id)
    elsif newest.sign_in_time > REPEAT_WINDOW.ago
      Toggle.new(:repeat, [], nil)
    else
      active_sessions.sign_out_session
      Toggle.new(:sign_out, [], nil)
    end
  end

  def open_session(user)
    LabSession.sign_in(user, @space, mac_address: @mac_address)
  end

  def finish_toggle(rfid, toggle)
    case toggle.outcome
    when :sign_out
      TapBoxLog.log_sign_out(user: rfid.user, card_number: rfid.card_number, space: @space, mac_address: @mac_address)
      StaffDashboardChannel.send_tap_out rfid.user, @space_id
      Result.new(:sign_out)
    when :sign_in
      announce_space_switch(rfid, toggle) if toggle.previous_space_id
      signed_in(rfid)
    else
      Result.new(:sign_in)
    end
  end

  def announce_space_switch(rfid, toggle)
    previous_space = Space.find_by(id: toggle.previous_space_id)
    TapBoxLog.log_sign_out(user: rfid.user, card_number: rfid.card_number, space: @space, mac_address: @mac_address, previous_space: previous_space)
    # The spaces the user left drop them from their tables
    toggle.left_space_ids.each { |space_id| StaffDashboardChannel.send_tap_out rfid.user, space_id }
  end

  # After the new session exists: log it, queue the membership check and the
  # live popup/table update.
  def signed_in(rfid)
    TapBoxLog.log_sign_in(user: rfid.user, card_number: rfid.card_number, space: @space, mac_address: @mac_address)
    TapBoxLog.log_membership_check_queued(user: rfid.user, card_number: rfid.card_number, space: @space, mac_address: @mac_address)
    CardTapJob.perform_later(rfid, @space_id)
    Result.new(:sign_in)
  end
end
