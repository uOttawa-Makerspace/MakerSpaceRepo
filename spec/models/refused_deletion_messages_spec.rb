# frozen_string_literal: true

require "rails_helper"

# A record that still has dependants cannot be destroyed. The refusal is worded for the model, in both
# languages, instead of Rails' generic text with the internal association name.
RSpec.describe "Refused deletion messages" do
  def refusal_in(locale, record)
    I18n.with_locale(locale) do
      record.errors.clear
      expect(record.destroy).to be(false)
      record.errors.full_messages
    end
  end


  {
    "membership tier" => [
      -> { create(:membership, membership_tier: create(:membership_tier)).membership_tier },
      "This membership tier has memberships and cannot be deleted.",
      "Ce niveau d'adhésion a des adhésions et ne peut pas être supprimé."
    ],
    "proficient project" => [
      -> { create(:proficient_project_session).proficient_project },
      "This project has sessions and cannot be deleted.",
      "Ce projet a des séances et ne peut pas être supprimé."
    ],
    "training with sessions" => [
      -> { create(:training_session).training },
      "This training has sessions or projects and cannot be deleted.",
      "Cette formation a des séances ou des projets et ne peut pas être supprimée."
    ],
    "training with projects" => [
      -> { create(:proficient_project).training },
      "This training has sessions or projects and cannot be deleted.",
      "Cette formation a des séances ou des projets et ne peut pas être supprimée."
    ],
    "printer type" => [
      -> { create(:printer, :UM3_01).printer_type },
      "This printer type has printers and cannot be deleted.",
      "Ce type d'imprimante a des imprimantes et ne peut pas être supprimé."
    ],
    "printer with sessions" => [
      -> { create(:printer_session, :um3_session).printer },
      "This printer has sessions or issues and cannot be removed.",
      "Cette imprimante a des séances ou des problèmes signalés et ne peut pas être retirée."
    ],
    "printer with issues" => [
      -> { create(:printer_issue).printer },
      "This printer has sessions or issues and cannot be removed.",
      "Cette imprimante a des séances ou des problèmes signalés et ne peut pas être retirée."
    ],
    "locker size" => [
      -> { create(:locker, locker_size: create(:locker_size)).locker_size },
      "This locker size has lockers and cannot be deleted.",
      "Cette taille de casier a des casiers et ne peut pas être supprimée."
    ],
    "booking status" => [
      -> { create(:sub_space_booking_status).booking_status },
      "This booking status is in use by bookings and cannot be deleted.",
      "Ce statut de réservation est utilisé par des réservations et ne peut pas être supprimé."
    ],
    "booking status entry" => [
      -> { create(:sub_space_booking).sub_space_booking_status },
      "This booking status entry is still used by a booking and cannot be deleted.",
      "Cette entrée de statut est encore utilisée par une réservation et ne peut pas être supprimée."
    ],
    "sub space" => [
      -> { create(:sub_space_booking).sub_space },
      "This sub space has bookings and cannot be deleted.",
      "Ce sous-espace a des réservations et ne peut pas être supprimé."
    ],
    "user with a card" => [
      -> { create(:rfid).user },
      "This user has an RFID card and cannot be deleted.",
      "Cet utilisateur a une carte RFID et ne peut pas être supprimé."
    ]
  }.each do |name, (build, english, french)|
    it "words the refusal for a #{name} in English and French" do
      record = instance_exec(&build)

      expect(refusal_in(:en, record)).to eq([english])
      expect(refusal_in(:fr, record)).to eq([french])
    end
  end
end
