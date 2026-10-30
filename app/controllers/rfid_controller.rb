# frozen_string_literal: true
include ActionView::Helpers::DateHelper

class RfidController < SessionsController
  # D-EQ04: the controller is named "rfid", so ParamsWrapper would nest a JSON
  # tap's params under :rfid and a tap without an rfid key made params[:rfid] a hash.
  wrap_parameters false

  # The tap boxes (frozen firmware) send no CSRF token and no session cookie; they are
  # authenticated by a registered reader's MAC (tap_reader). A tap that comes with a
  # cookie session (the React app's staff path) is authenticated by that cookie, so
  # it stays CSRF-checked (or goes through the legacy JSON exemption).
  # One condition, not `only:` + `if:`: a skip with both is applied when EITHER holds.
  skip_forgery_protection if: :tap_without_session?

  before_action :signed_in, only: %i[get_unset_rfids]
  before_action :grant_access, only: %i[get_unset_rfids]

  # D-EQ03: 60 taps/min per reader (mac AND source IP: a real reader taps from a
  # fixed IP, so someone replaying a known MAC from elsewhere only exhausts their
  # own bucket and cannot lock the real door out) or per staff user, plus a coarse
  # 600/min per-IP ceiling (readers may share one NAT egress IP).
  RATE_LIMITED = -> { render json: { error: "Too many requests" }, status: :too_many_requests }
  rate_limit to: 60, within: 1.minute, only: :card_number, name: "tap",
             by: -> { tap_rate_limit_key }, with: RATE_LIMITED
  rate_limit to: 600, within: 1.minute, only: :card_number, name: "tap-ip",
             by: -> { request.remote_ip }, with: RATE_LIMITED

  # Rejected taps (unknown MAC, 401) are counted per IP and capped much tighter,
  # to slow brute-forcing of a reader's MAC. Only rejections count, so a real
  # reader on the same IP is never throttled by them.
  REJECTED_TAPS_PER_MINUTE = 10

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
            "Tapped at #{PiReader.find_by_mac(card.mac_address).space.name} #{time_ago_in_words(card.updated_at)} ago"
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

    # D-EQ01/D-EQ03: no staff auth and no registered reader -> no PiReader, Rfid,
    # LabSession or broadcast; only the bounded unregistered-reader trace is
    # logged (one row per MAC per hour, not broadcast).
    # A reader with no space (e.g. legacy rows the old self-registration created
    # for any MAC) is not registered until an admin associates it with a space.
    unless staff || pi_reader&.space
      return render json: { error: "Too many requests" }, status: :too_many_requests if rejected_taps_exceeded?

      TapBoxLog.log_unknown_reader(mac_address: tap_mac_address)
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

    result = RfidTap.call(card: card, space: space, mac_address: mac_address, tap_start: tap_start)
    case result.outcome
    when :sign_in, :sign_out
      render json: user_response_payload(result.success_message), status: :ok
    when :unlinked_card
      render json: { error: "Temporary RFID already exists" }, status: :unprocessable_content
    when :new_card
      render json: { new_rfid: "Temporary RFID created" }, status: :unprocessable_content
    else
      render json: { new_rfid: "Error, requires rfid param" }, status: :unprocessable_content
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

  def tap_without_session?
    action_name == "card_number" && session_user.nil?
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

  def rejected_taps_exceeded?
    count = RateLimitCounter.increment("rate-limit:rfid:rejected:#{request.remote_ip}", 1, expires_in: 1.minute)
    count > REJECTED_TAPS_PER_MINUTE
  end

  def tap_rate_limit_key
    if tap_staff?
      "staff:#{current_user.id}"
    elsif tap_mac_address
      "mac:#{tap_mac_address}|ip:#{request.remote_ip}"
    else
      "ip:#{request.remote_ip}"
    end
  end

  # Pi firmware and the React app read only `success`; nothing about the card
  # owner is returned (D-EQ02).
  def user_response_payload(success_message)
    { success: success_message }
  end

  def grant_access
    return if current_user.staff?
    flash[:alert] = "You cannot access this area."
    redirect_to root_path
  end
end