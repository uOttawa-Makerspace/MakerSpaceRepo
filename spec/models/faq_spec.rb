require "rails_helper"

RSpec.describe Faq, type: :model do
  it "is valid with the four localized fields" do
    expect(build(:faq)).to be_valid
  end

  %i[title_en title_fr body_en body_fr].each do |field|
    it "requires #{field}" do
      faq = build(:faq, field => "")
      expect(faq).not_to be_valid
      expect(faq.errors[field]).to be_present
    end
  end

  describe "order" do
    it "allows nil and integers" do
      expect(build(:faq, order: nil)).to be_valid
      expect(build(:faq, order: 3)).to be_valid
    end

    it "rejects non-integers" do
      expect(build(:faq, order: 1.5)).not_to be_valid
      expect(build(:faq, order: "abc")).not_to be_valid
    end

    it "default scope sorts by order" do
      b = create(:faq, order: 2)
      a = create(:faq, order: 1)
      expect(Faq.all.to_a).to eq([a, b])
    end

    it "sorts NULL orders last (Postgres ASC default)" do
      unordered = create(:faq, order: nil)
      first = create(:faq, order: 1)
      expect(Faq.all.to_a).to eq([first, unordered])
    end
  end

  describe "#localized_title / #localized_body" do
    let(:faq) { build(:faq, title_en: "Hello", title_fr: "Bonjour", body_en: "Body", body_fr: "Corps") }

    after { I18n.locale = I18n.default_locale }

    it "uses English by default and French for :fr" do
      I18n.locale = :en
      expect([faq.localized_title, faq.localized_body]).to eq(%w[Hello Body])
      I18n.locale = :fr
      expect([faq.localized_title, faq.localized_body]).to eq(%w[Bonjour Corps])
    end
  end
end
