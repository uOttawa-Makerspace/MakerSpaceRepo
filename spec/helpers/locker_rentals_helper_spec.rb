# frozen_string_literal: true

require "rails_helper"

RSpec.describe LockerRentalsHelper, type: :helper do
  describe "#requested_as_label" do
    it "names each request type in the page language" do
      labels = %w[general staff student].map { |type| helper.requested_as_label(LockerRental.new(requested_as: type)) }
      french = I18n.with_locale(:fr) { %w[general staff student].map { |type| helper.requested_as_label(LockerRental.new(requested_as: type)) } }

      expect(labels).to eq(%w[General Staff Student])
      expect(french).to eq(%w[Général Personnel Étudiant])
    end

    it "is blank for a rental with no recorded request type" do
      expect(helper.requested_as_label(LockerRental.new(requested_as: nil))).to eq("")
    end
  end

  describe "#locker_rental_state_display" do
    it "names the state in the page language" do
      rental = LockerRental.new(state: :await_payment)

      expect(Nokogiri::HTML(helper.locker_rental_state_display(rental)).text).to eq("Await payment")
      expect(Nokogiri::HTML(I18n.with_locale(:fr) { helper.locker_rental_state_display(rental) }).text).to eq("En attente de paiement")
    end
  end
end
