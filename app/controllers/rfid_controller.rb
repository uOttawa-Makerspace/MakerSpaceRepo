# frozen_string_literal: true
include ActionView::Helpers::DateHelper

class RfidController < SessionsController
  # D-EQ04: the controller is named "rfid", so ParamsWrapper would nest a JSON
  # tap's params under :rfid and a tap without an rfid key made params[:rfid] a hash.
  wrap_parameters false

  before_action :signed_in, only: %i[get_unset_rfids]
  before_action :grant_access, only: %i[get_unset_rfids]

  # D-EQ03: per reader (mac) or per staff user, generous for a busy door; plus a
  # coarse per-IP ceiling (readers may share one NAT egress IP) that caps floods
  # of made-up MACs.
  RATE_LIMITED = -> { render json: { error: "Too many requests" }, status: :too_many_requests }
  rate_limit to: 60, within: 1.minute, only: :card_number, name: "tap",
             by: -> { tap_rate_limit_key }, with: RATE_LIMITED
  rate_limit to: 600, within: 1.minute, only: :card_number, name: "tap-ip",
             by: -> { request.remote_ip }, with: RATE_LIMITED

  # Shows the list of student cards tapped for staff members to link to newly
  # signed up users
  def get_unset_rfids
    rfids = []
    mac_addresses =
      PiReader.where(space: @user.space || Space.all).pluck(:pi_mac_address)

    Rfid
      .recent_unset
      .where(mac_address: mac_addresses)
      .first(5)
      .each do |card|
        rfids << {
          cardNumber: card.card_number,
          tappedAt:
            "Tapped at #{PiReader.find_by(pi_mac_address: card.mac_address).space.name} #{time_ago_in_words(card.updated_at)} ago"
        }
      end
    render json: rfids
  end

  # Notify server of a student card tap. Two callers:
  # - Raspberry Pi readers (frozen firmware): JSON {rfid, mac_address}, no
  #   credentials. Accepted only when mac_address belongs to a PiReader an admin
  #   registered; the reader's space decides where the tap lands.
  # - The React app: a staff/admin session or Bearer JWT with {rfid, space_id}.
  def card_number
    tap_start = Time.current

    card = params[:rfid] if params[:rfid].is_a?(String)
    pi_reader = tap_reader
    staff = tap_staff?
    mac_address = tap_mac

    # D-EQ01/D-EQ03: no staff auth and no registered reader -> nothing is
    # created, logged or broadcast.
    unless staff || pi_reader
      return render json: { error: "Unauthorized" }, status: :unauthorized
    end

    TapBoxLog.log_card_tap(
      card_number: card,
      mac_address: mac_address,
      space_id_param: params[:space_id]
    )

    # --- Resolve space ---
    space = Space.find_by(id: params[:space_id].to_s) if staff && params[:space_id].present?
    space ||= pi_reader&.space
    space_id = space&.id

    unless space_id
      TapBoxLog.log_no_space_resolved(card_number: card, mac_address: mac_address)
      return render json: { new_rfid: "Error, missing space_id or mac_address param" }, status: :unprocessable_content
    end

    # --- Look up RFID ---
    rfid = Rfid.find_by(card_number: card)

    if rfid
      if rfid.user_id
        # User has a card associated with their account
        user = rfid.user
        elapsed_ms = ((Time.current - tap_start) * 1000).round(1)
        TapBoxLog.log_card_recognized(user: user, card_number: card, space: space, mac_address: mac_address, elapsed_ms: elapsed_ms)
        check_session(rfid, space_id)
      else
        rfid.mac_address = mac_address
        rfid.touch
        rfid.save
        TapBoxLog.log_unlinked_card(card_number: card, space: space, mac_address: mac_address)
        render json: { error: "Temporary RFID already exists" }, status: :unprocessable_content
      end
    else
      new_rfid = Rfid.create(card_number: card, mac_address: mac_address)
      if new_rfid.valid?
        TapBoxLog.log_new_unknown_card(card_number: card, space: space, mac_address: mac_address)
        render json: { new_rfid: "Temporary RFID created" }, status: :unprocessable_content
      else
        TapBoxLog.log_invalid_rfid(card_number: card, mac_address: mac_address, errors: new_rfid.errors.full_messages)
        render json: { new_rfid: "Error, requires rfid param" }, status: :unprocessable_content
      end
    end
  end

  def update_kiosk(space_id)
    @space = Space.find(space_id)
    @certifications_on_space =
      proc do |user, space_id|
        user
          .certifications
          .joins(:training, training: :spaces)
          .where(trainings: { spaces: { id: space_id } })
      end
    @all_user_certs = proc { |user| user.certifications }
  end

  private

  # The caller's MAC as a normalized string, or nil (never a hash/array param).
  def tap_mac_address
    return @tap_mac_address if defined?(@tap_mac_address)

    @tap_mac_address = PiReader.normalize_mac(params[:mac_address])
  end

  def tap_reader
    return @tap_reader if defined?(@tap_reader)

    @tap_reader = tap_mac_address && PiReader.find_by_mac(tap_mac_address)
  end

  def tap_staff?
    return @tap_staff if defined?(@tap_staff)

    @tap_staff = signed_in? && current_user.staff?
  end

  # The MAC stored on LabSession/Rfid/TapBoxLog rows: the registered reader's own
  # value (so it matches PiReader exactly), else the normalized param.
  def tap_mac
    tap_reader&.pi_mac_address || tap_mac_address
  end

  def tap_rate_limit_key
    if tap_staff?
      "staff:#{current_user.id}"
    elsif tap_mac_address
      "mac:#{tap_mac_address}"
    else
      "ip:#{request.remote_ip}"
    end
  end

  # Pi firmware and the React app read only `success`; nothing about the card
  # owner is returned (D-EQ02).
  def user_response_payload(success_message)
    { success: success_message }
  end

  def check_session(rfid, space_id)
    active_sessions = rfid.user.lab_sessions.active
    space = Space.find_by(id: space_id)

    if active_sessions.present?
      # Sign out of all spaces
      active_sessions.sign_out_session
      # If user tapped somewhere other than last active space, make a new
      # session.
      last_active_location = active_sessions.last.space_id

      if last_active_location != space_id
        previous_space = Space.find_by(id: last_active_location)
        TapBoxLog.log_sign_out(user: rfid.user, card_number: rfid.card_number, space: space, mac_address: tap_mac, previous_space: previous_space)
        new_session(rfid, space_id)
      else
        TapBoxLog.log_sign_out(user: rfid.user, card_number: rfid.card_number, space: space, mac_address: tap_mac)
        StaffDashboardChannel.send_tap_out rfid.user, space_id
        render json: user_response_payload("RFID sign out"), status: :ok
      end
    else
      new_session(rfid, space_id)
      TapBoxLog.log_membership_check_queued(user: rfid.user, card_number: rfid.card_number, space: space, mac_address: tap_mac)
      CardTapJob.perform_later(rfid, space_id)
    end
    # While membership check is running, return an HTTP code to card scanner to
    # signal if an account is associated with the RFID number
  end

  def new_session(rfid, new_location)
    space = Space.find_by(id: new_location)

    LabSession.create_session(
      user: rfid.user,
      mac_address: tap_mac,
      space_id: new_location
    )

    TapBoxLog.log_sign_in(user: rfid.user, card_number: rfid.card_number, space: space, mac_address: tap_mac)
    render json: user_response_payload("RFID sign in"), status: :ok
  end

  def grant_access
    return if current_user.staff?
    flash[:alert] = "You cannot access this area."
    redirect_to root_path
  end
end