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
    if params[:space_id].present? && Space.find(params[:space_id]).present?
      space_id = params[:space_id]
    else
      unless PiReader.find_by(pi_mac_address: params[:mac_address])
        new_reader = PiReader.new(pi_mac_address: params[:mac_address])
        new_reader.save
      end

      space_id = PiReader.find_by(pi_mac_address: params[:mac_address]).space_id
    end

    rfid = Rfid.find_by(card_number: params[:rfid])

    unless space_id
      return(
        render json: {
                 new_rfid: "Error, missing space_id or mac_address param"
               },
               status: :unprocessable_entity
      )
    end

    if rfid
      if rfid.user_id
        check_session(rfid, space_id)
      else
        rfid.mac_address = params[:mac_address]
        rfid.touch
        rfid.save
        render json: {
                 error: "Temporary RFID already exists"
               },
               status: :unprocessable_entity
      end
    else
      new_rfid =
        Rfid.create(
          card_number: params[:rfid],
          mac_address: params[:mac_address]
        )
      if new_rfid.valid?
        render json: {
                 new_rfid: "Temporary RFID created"
               },
               status: :unprocessable_entity
      else
        render json: {
                 new_rfid: "Error, requires rfid param"
               },
               status: :unprocessable_entity
      end
    end
  end

  private

  def update_kiosk(space_id)
    @space = Space.find(space_id)
    @certifications_on_space =
      Proc.new do |user, space_id|
        user
          .certifications
          .joins(:training, training: :spaces)
          .where(trainings: { spaces: { id: space_id } })
      end
    @all_user_certs = Proc.new { |user| user.certifications }
  end
  def check_session(rfid, space_id)
    active_sessions =
      rfid.user.lab_sessions.where("sign_out_time > ?", Time.zone.now)
    if active_sessions.present?
      active_sessions.update_all(sign_out_time: Time.zone.now)
      last_active_location = active_sessions.last.space_id
      if last_active_location != space_id
        new_session(rfid, space_id)
      else
        render json: { success: "RFID sign out" }, status: :ok
      end
    else
      new_session(rfid, space_id)
    end
    update_kiosk(space_id)
  end

  def new_session(rfid, new_location)
    sign_in = Time.zone.now
    sign_out = sign_in + 6.hours
    new_session =
      rfid.user.lab_sessions.new(
        sign_in_time: sign_in,
        sign_out_time: sign_out,
        mac_address: params[:mac_address],
        space_id: new_location
      )
    new_session.save
    render json: { success: "RFID sign in" }, status: :ok
  end

  def grant_access
    unless current_user.staff? || current_user.admin?
      flash[:alert] = "You cannot access this area."
      redirect_to root_path
    end
  end
end
