# frozen_string_literal: true

require "rails_helper"

RSpec.describe SubSpaceBookingHelper, type: :helper do
  describe "#booking_rules" do
    let(:limited_room) do
      build(:sub_space, maximum_booking_duration: 4, maximum_booking_hours_per_week: 10,
                        default_public: true, approval_required: true, max_automatic_approval_hour: 2)
    end

    it "lists no rules for a room without limits, approval or public default" do
      expect(helper.booking_rules(build(:sub_space))).to eq([])
    end

    it "lists every rule in order, the approval rule with the automatic-approval hours" do
      expect(helper.booking_rules(limited_room)).to eq(
        ["has a maximum booking duration of 4 hours",
         "has a maximum booking hours per person per week of 10 hours",
         "bookings (Name and Description of event) are public by default",
         "Bookings require manual approval, bookings of 2 hours or less will be automatically approved"]
      )
    end

    it "says bookings need manual approval when there are no automatic-approval hours" do
      expect(helper.booking_rules(build(:sub_space, approval_required: true)))
        .to eq(["bookings will require manual approval"])
    end

    it "ignores the automatic-approval hours of a room that needs no approval" do
      expect(helper.booking_rules(build(:sub_space, max_automatic_approval_hour: 3))).to eq([])
    end

    it "lists the rules in French on a French page" do
      manual = build(:sub_space, approval_required: true)
      french = I18n.with_locale(:fr) { [helper.booking_rules(limited_room), helper.booking_rules(manual)] }

      expect(french).to eq(
        [["a une durée maximale de réservation de 4 heures",
          "a un maximum de 10 heures de réservation par personne par semaine",
          "les réservations (nom et description de l'événement) sont publiques par défaut",
          "Les réservations nécessitent une approbation manuelle, les réservations de 2 heures ou moins " \
          "seront approuvées automatiquement"],
         ["les réservations nécessiteront une approbation manuelle"]]
      )
    end
  end
end
