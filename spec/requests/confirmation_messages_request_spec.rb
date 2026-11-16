# frozen_string_literal: true

require "rails_helper"

# The text a confirming button asks comes from the locale files, so a page in French asks in
# French, and a message that names its item carries that item's name (escaped, because it is
# an HTML attribute read by window.confirm).
RSpec.describe "Confirmation messages", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:user) { create(:user, :regular_user) }

  before { block_external_http! }

  def messages
    Nokogiri::HTML(response.body).css("[data-confirmation-message-value]").map { |node| node["data-confirmation-message-value"] }
  end

  describe "a message without an item" do
    before do
      create(:drop_off_location, name: "Dock")
      shop_log_in!(admin)
    end

    it "is in English by default" do
      get admin_drop_off_locations_path
      expect(messages).to eq([I18n.t("confirmations.drop_off_locations.delete", name: "Dock", locale: :en)])
      expect(messages.first).to eq('Delete the drop-off location "Dock"?')
    end

    it "is in French on a French page" do
      get admin_drop_off_locations_path(locale: "fr")
      expect(messages).to eq(["Supprimer le lieu de dépôt « Dock »?"])
    end
  end

  describe "a message that names the location" do
    it "carries the name, with quotes kept intact in the attribute" do
      create(:drop_off_location, name: 'Dock "A"')
      shop_log_in!(admin)
      get admin_drop_off_locations_path
      expect(messages).to eq(['Delete the drop-off location "Dock "A""?'])
    end

    it "names the location on the edit page too" do
      location = create(:drop_off_location, name: "Dock")
      shop_log_in!(admin)
      get edit_admin_drop_off_location_path(location, locale: "fr")
      expect(messages).to eq(["Supprimer le lieu de dépôt « Dock »?"])
    end
  end

  describe "a message that names the coupon code" do
    it "carries the code in both languages" do
      coupon = create(:coupon_code, :unclaimed, code: "SAVE5")
      shop_log_in!(admin)
      get coupon_codes_path
      expect(messages).to eq(['Delete the coupon code "SAVE5"?'])
      get coupon_codes_path(locale: "fr")
      expect(messages).to eq(["Supprimer le code de coupon « SAVE5 »?"])
      expect(coupon).to be_persisted
    end
  end

  describe "a message that names the cost" do
    it "carries the CC cost in both languages" do
      create(:coupon_code, :unclaimed, dollar_cost: 5, cc_cost: 50)
      shop_log_in!(user)
      get new_discount_code_path
      expect(messages).to eq(["Buy the coupon for 50 CC? This cannot be undone."])
      get new_discount_code_path(locale: "fr")
      expect(messages).to eq(["Acheter le coupon pour 50 CC? Cette action est irréversible."])
    end
  end
end
