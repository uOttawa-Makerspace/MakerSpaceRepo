# frozen_string_literal: true

require "rails_helper"

# The flash messages of the booking pages, answered in the request's language. Each case runs once in English
# (the wording as it always was) and once in French.
RSpec.describe "Sub space booking messages by language", :booking_clock, type: :request do
  before do
    @pending_status = create(:booking_status, :pending)
    @approved_status = create(:booking_status, :approved)
    create(:booking_status, :rejected)
  end

  let(:subspace) { create(:sub_space, name: "Salle A") }
  let(:owner) { create(:user, :regular_user, booking_approval: true) }
  let(:admin) { create(:user, :admin, booking_approval: true) }

  def log_in!(account)
    post login_authentication_path, params: { username_email: account.username, password: "asa32A353#" }
    follow_redirect!
  end

  def booking(status: @pending_status, user: owner, **attrs)
    create(:sub_space_booking, { sub_space: subspace, user: user,
                                 start_time: DateTime.parse("2027-04-03 10:00"),
                                 end_time: DateTime.parse("2027-04-03 11:00") }.merge(attrs))
      .tap { |row| row.change_status!(status) }
  end

  def access_request(status:)
    user = create(:user, :regular_user, name: "Alex Doe", booking_approval: status == "approved")
    UserBookingApproval.create!(user: user, identity: "Other", status: status, staff: (admin if status == "approved"),
                                comments: "c", date: Date.new(2027, 1, 1))
  end

  def booking_params(**extra)
    { sub_space_booking: { sub_space_id: subspace.id, start_time: "2027-03-03 10:00", end_time: "2027-03-03 11:00",
                           name: "N", description: "D" }.merge(extra) }
  end

  def self.both_languages(description, flash_key, english, french, &block)
    { "en" => english, "fr" => french }.each do |locale, text|
      it "#{description} (#{locale})" do
        instance_exec(locale, &block)
        expect(flash[flash_key]).to eq(text)
      end
    end
  end

  describe "access requests" do
    before { log_in!(create(:user, :regular_user, booking_approval: false)) }

    both_languages "asks for a reason", :alert,
                   "Please provide a reason for booking access.",
                   "Veuillez indiquer la raison de votre demande d'accès aux réservations." do |locale|
      put request_access_sub_space_booking_index_path(locale: locale), params: { comments: "" }
    end

    both_languages "asks for a supervisor", :alert,
                   "Please choose a staff member as your supervisor.",
                   "Veuillez choisir un membre du personnel comme superviseur." do |locale|
      put request_access_sub_space_booking_index_path(locale: locale), params: { comments: "c", identity: "Staff" }
    end

    both_languages "confirms the request", :notice,
                   "Access request submitted successfully.", "Votre demande d'accès a été envoyée." do |locale|
      put request_access_sub_space_booking_index_path(locale: locale), params: { comments: "c", identity: "GNG" }
    end
  end

  describe "access decisions" do
    before { log_in!(admin) }

    both_languages "grants access", :notice, "Access granted successfully.", "L'accès a été accordé." do |locale|
      put approve_access_sub_space_booking_index_path(locale: locale),
          params: { user_id: create(:user, :regular_user, booking_approval: false).id }
    end

    both_languages "approves a request", :notice,
                   "Access request approved successfully.", "La demande d'accès a été approuvée." do |locale|
      put approve_access_sub_space_booking_index_path(locale: locale), params: { id: access_request(status: "pending").id }
    end

    both_languages "says access is already held", :notice,
                   "Alex Doe already has booking access.", "Alex Doe a déjà accès aux réservations." do |locale|
      put approve_access_sub_space_booking_index_path(locale: locale),
          params: { user_id: access_request(status: "approved").user_id }
    end

    both_languages "revokes access", :notice,
                   "Booking access revoked successfully.", "L'accès aux réservations a été retiré." do |locale|
      put deny_access_sub_space_booking_index_path(locale: locale), params: { id: access_request(status: "approved").id }
    end

    both_languages "declines a request", :notice,
                   "Access request declined successfully.", "La demande d'accès a été refusée." do |locale|
      put deny_access_sub_space_booking_index_path(locale: locale), params: { id: access_request(status: "pending").id }
    end

    both_languages "needs selected approvals", :alert, "No approvals selected.", "Aucune demande sélectionnée." do |locale|
      put bulk_approve_access_sub_space_booking_index_path(locale: locale)
    end

    both_languages "needs selected bookings", :alert,
                   "No bookings selected.", "Aucune réservation sélectionnée." do |locale|
      put bulk_approve_decline_sub_space_booking_index_path(locale: locale), params: { bulk_status: "approve" }
    end
  end

  describe "booking decisions" do
    before { log_in!(admin) }

    both_languages "approves a booking", :notice,
                   "Booking for Salle A approved successfully.", "La réservation de Salle A a été approuvée." do |locale|
      put sub_space_booking_approve_path(sub_space_booking_id: booking.id, locale: locale)
    end

    both_languages "declines a booking", :notice,
                   "Booking for Salle A declined successfully.", "La réservation de Salle A a été refusée." do |locale|
      put sub_space_booking_decline_path(sub_space_booking_id: booking.id, locale: locale)
    end

    both_languages "says a booking is no longer pending", :alert,
                   "Booking for Salle A is no longer pending.",
                   "La réservation de Salle A n'est plus en attente." do |locale|
      put sub_space_booking_approve_path(sub_space_booking_id: booking(status: @approved_status).id, locale: locale)
    end

    both_languages "makes a booking public", :notice,
                   "Booking made public successfully.", "La réservation est maintenant publique." do |locale|
      put sub_space_booking_publish_path(sub_space_booking_id: booking(public: false).id, locale: locale)
    end

    both_languages "makes a booking private", :notice,
                   "Booking made private successfully.", "La réservation est maintenant privée." do |locale|
      put sub_space_booking_publish_path(sub_space_booking_id: booking(public: true).id, locale: locale)
    end
  end

  describe "an owner's bookings" do
    before { log_in!(owner) }

    both_languages "creates a booking", :notice,
                   "Booking for Salle A created successfully.", "La réservation de Salle A a été créée." do |locale|
      post sub_space_booking_index_path(locale: locale), params: booking_params
    end

    both_languages "refuses a block", :alert,
                   "You do not have permission to block a space.",
                   "Vous n'avez pas la permission de bloquer un espace." do |locale|
      post sub_space_booking_index_path(locale: locale), params: booking_params(blocking: "1")
    end

    both_languages "updates a booking", :notice,
                   "Successfully updated booking", "La réservation a été mise à jour." do |locale|
      patch sub_space_booking_update_path(sub_space_booking_id: booking.id, locale: locale),
            params: { sub_space_booking: { name: "Moved" } }
    end

    both_languages "refuses to open an approved booking", :alert,
                   "You can't access this subspace booking.", "Vous n'avez pas accès à cette réservation." do |locale|
      get sub_space_booking_edit_path(sub_space_booking_id: booking(status: @approved_status).id, locale: locale)
    end

    both_languages "refuses to change an approved booking", :alert,
                   "You do not have permission to edit this booking",
                   "Vous n'avez pas la permission de modifier cette réservation." do |locale|
      patch sub_space_booking_update_path(sub_space_booking_id: booking(status: @approved_status).id, locale: locale),
            params: { sub_space_booking: { name: "Moved" } }
    end

    both_languages "deletes a booking", :notice,
                   "Booking for Salle A deleted successfully.", "La réservation de Salle A a été supprimée." do |locale|
      delete sub_space_booking_delete_path(booking.id, locale: locale)
    end

    both_languages "deletes the rest of a series", :notice,
                   "Remaining bookings for Salle A deleted successfully.",
                   "Les réservations restantes de Salle A ont été supprimées." do |locale|
      delete delete_remaining_recurring_sub_space_booking_path(booking(recurring_booking: RecurringBooking.create!).id,
                                                               locale: locale)
    end

    both_languages "says a booking is not part of a series", :notice,
                   "Booking is not attached to a recurring booking.",
                   "Cette réservation ne fait pas partie d'une série récurrente." do |locale|
      delete delete_remaining_recurring_sub_space_booking_path(booking.id, locale: locale)
    end
  end

  describe "refusals" do
    let(:stranger) { create(:user, :regular_user, booking_approval: true) }

    both_languages "asks a guest to log in", :alert,
                   "You must be logged in to view this page.", "Vous devez être connecté pour voir cette page." do |locale|
      get sub_space_booking_index_path(locale: locale)
    end

    both_languages "needs booking approval to book", :alert,
                   "You must be approved to book to view this page.",
                   "Vous devez être autorisé à réserver pour voir cette page." do |locale|
      log_in!(create(:user, :regular_user, booking_approval: false))
      post sub_space_booking_index_path(locale: locale), params: booking_params
    end

    both_languages "needs staff to decide", :alert,
                   "You must be an admin or staff to view this page.",
                   "Vous devez être administrateur ou membre du personnel pour voir cette page." do |locale|
      log_in!(stranger)
      put sub_space_booking_approve_path(sub_space_booking_id: booking.id, locale: locale)
    end

    both_languages "needs an admin to publish", :alert,
                   "You must be an admin to view this page.",
                   "Vous devez être administrateur pour voir cette page." do |locale|
      log_in!(stranger)
      put sub_space_booking_publish_path(sub_space_booking_id: booking.id, locale: locale)
    end

    both_languages "needs the owner to delete", :alert,
                   "You must be the owner of this booking or an admin to delete it.",
                   "Vous devez être le propriétaire de cette réservation ou un administrateur pour la supprimer." do |locale|
      log_in!(stranger)
      delete sub_space_booking_delete_path(booking.id, locale: locale)
    end

    both_languages "needs the owner to delete a series", :alert,
                   "You are not authorized to view this page.", "Vous n'êtes pas autorisé à voir cette page." do |locale|
      log_in!(stranger)
      delete delete_remaining_recurring_sub_space_booking_path(booking.id, locale: locale)
    end
  end
end
