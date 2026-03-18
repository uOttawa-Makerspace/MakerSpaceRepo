# frozen_string_literal: true
include ActionView::Helpers::DateHelper

class RfidController < SessionsController
  before_action :signed_in, only: %i[get_unset_rfids]
  before_action :grant_access, only: %i[get_unset_rfids]

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

  # Notify server of a student card tap
  def card_number
    tap_start = Time.current

    TapBoxLog.log!(
      event_type: TapBoxLog::CARD_TAP,
      message: "Card tapped on reader",
      card_number: params[:rfid],
      mac_address: params[:mac_address],
      details: {
        rfid: params[:rfid],
        mac_address: params[:mac_address],
        space_id_param: params[:space_id]
      }
    )

    # --- Resolve space ---
    if params[:space_id].present? && Space.find_by(id: params[:space_id]).present?
      space_id = params[:space_id]
    else
      pi_reader = PiReader.find_by(pi_mac_address: params[:mac_address])

      unless pi_reader
        pi_reader = PiReader.create(pi_mac_address: params[:mac_address])
        TapBoxLog.log!(
          event_type: TapBoxLog::INFO,
          message: "New Pi reader registered (not yet linked to a space)",
          card_number: params[:rfid],
          mac_address: params[:mac_address]
        )
      end

      space_id = pi_reader.space_id
    end

    space = space_id ? Space.find_by(id: space_id) : nil

    unless space_id
      TapBoxLog.log!(
        event_type: TapBoxLog::ERROR,
        message: "No space resolved — reader not linked to any space",
        card_number: params[:rfid],
        mac_address: params[:mac_address],
        details: { reason: "no_space", suggestion: "Link this Pi reader to a space in admin settings" }
      )
      return(
        render json: {
                 new_rfid: "Error, missing space_id or mac_address param"
               },
               status: :unprocessable_content
      )
    end

    # --- Look up RFID ---
    rfid = Rfid.find_by(card_number: params[:rfid])

    if rfid
      if rfid.user_id
        # User has a card associated with their account
        user = rfid.user
        TapBoxLog.log!(
          event_type: TapBoxLog::INFO,
          message: "Card recognized → #{user.name} (ID: #{user.id})",
          card_number: params[:rfid],
          user: user,
          space: space,
          mac_address: params[:mac_address],
          details: {
            user_email: user.email,
            user_username: user.username,
            resolve_time_ms: ((Time.current - tap_start) * 1000).round(1)
          }
        )
        check_session(rfid, space_id)
      else
        rfid.mac_address = params[:mac_address]
        rfid.touch
        rfid.save
        TapBoxLog.log!(
          event_type: TapBoxLog::WARNING,
          message: "Card exists but is NOT linked to any user — box will not flash green",
          card_number: params[:rfid],
          space: space,
          mac_address: params[:mac_address],
          details: {
            reason: "unlinked_card",
            suggestion: "Link this card to a user via the staff dashboard"
          }
        )
        render json: {
                 error: "Temporary RFID already exists"
               },
               status: :unprocessable_content
      end
    else
      new_rfid =
        Rfid.create(
          card_number: params[:rfid],
          mac_address: params[:mac_address]
        )
      if new_rfid.valid?
        TapBoxLog.log!(
          event_type: TapBoxLog::WARNING,
          message: "Brand new unknown card — temporary RFID created, needs linking",
          card_number: params[:rfid],
          space: space,
          mac_address: params[:mac_address],
          details: {
            reason: "new_unknown_card",
            suggestion: "This could be a new student card, a replacement card, or a mistyped student number"
          }
        )
        render json: {
                 new_rfid: "Temporary RFID created"
               },
               status: :unprocessable_content
      else
        TapBoxLog.log!(
          event_type: TapBoxLog::ERROR,
          message: "Failed to create RFID record — validation error",
          card_number: params[:rfid],
          mac_address: params[:mac_address],
          details: {
            reason: "invalid_rfid",
            errors: new_rfid.errors.full_messages
          }
        )
        render json: {
                 new_rfid: "Error, requires rfid param"
               },
               status: :unprocessable_content
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

  # FIXME: These should be moved to LabSession model

  # Check if a user has an active session for the space they tapped in, sign out
  # of all active sessions and create a new session in space unless user just
  # signed out of it.
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
        TapBoxLog.log!(
          event_type: TapBoxLog::SIGN_OUT,
          message: "#{rfid.user.name} signed out of #{Space.find_by(id: last_active_location)&.name || 'unknown'} (switching spaces)",
          card_number: rfid.card_number,
          user: rfid.user,
          space: space,
          mac_address: params[:mac_address],
          details: { previous_space_id: last_active_location, action: "space_switch" }
        )
        new_session(rfid, space_id)
      else
        # Notify staff dashboard of user sign out
        TapBoxLog.log!(
          event_type: TapBoxLog::SIGN_OUT,
          message: "#{rfid.user.name} signed out of #{space&.name}",
          card_number: rfid.card_number,
          user: rfid.user,
          space: space,
          mac_address: params[:mac_address]
        )
        StaffDashboardChannel.send_tap_out rfid.user, space_id
        render json: { success: "RFID sign out" }, status: :ok
      end
    else
      new_session(rfid, space_id)

      # Here we're assuming the user is physically in the space. Query if they
      # are eligible for a faculty membership and later send a notification to
      # the staff dashboard
      TapBoxLog.log!(
        event_type: TapBoxLog::INFO,
        message: "Queuing membership eligibility check for #{rfid.user.name}",
        card_number: rfid.card_number,
        user: rfid.user,
        space: space,
        mac_address: params[:mac_address]
      )
      CardTapJob.perform_later(rfid, space_id)
    end
    # While membership check is running, return an HTTP code to card scanner to
    # signal if an account is associated with the RFID number
  end

  def new_session(rfid, new_location)
    space = Space.find_by(id: new_location)

    session = LabSession.create_session(
      user: rfid.user,
      mac_address: params[:mac_address],
      space_id: new_location
    )

    TapBoxLog.log!(
      event_type: TapBoxLog::SIGN_IN,
      message: "#{rfid.user.name} signed into #{space&.name}",
      card_number: rfid.card_number,
      user: rfid.user,
      space: space,
      mac_address: params[:mac_address]
    )

    render json: { success: "RFID sign in" }, status: :ok
  end

  def grant_access
    return if current_user.staff?
      flash[:alert] = "You cannot access this area."
      redirect_to root_path
  end
end