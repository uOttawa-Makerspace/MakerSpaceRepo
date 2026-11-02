# frozen_string_literal: true

require "rails_helper"

RSpec.describe MembershipTier, type: :model do
  it { should have_many(:memberships) }
  it { should validate_presence_of(:title_en) }
  it { should validate_presence_of(:title_fr) }
  it { should validate_numericality_of(:internal_price).is_greater_than_or_equal_to(0) }
  it { should validate_numericality_of(:external_price).is_greater_than_or_equal_to(0) }
  it { should validate_numericality_of(:duration).only_integer.is_greater_than(0) }

  describe "#title" do
    let(:tier) { build(:membership_tier, title_en: "Day", title_fr: "Jour") }

    it "picks the FR title only for the :fr symbol locale" do
      expect(tier.title(:fr)).to eq("Jour")
      expect(tier.title(:en)).to eq("Day")
      expect(tier.title("fr")).to eq("Day") # string locale falls through
    end

    it "defaults to I18n.locale" do
      I18n.with_locale(:fr) { expect(tier.title).to eq("Jour") }
      expect(tier.title).to eq("Day")
    end
  end

  describe "#price" do
    let(:tier) { build(:membership_tier, internal_price: 10, external_price: 25) }

    it "charges internal identities the internal price and everyone else the external price" do
      internal = build(:user, identity: User::INTERNAL_IDENTITIES.first)
      external = build(:user, identity: "definitely_not_internal")
      expect(tier.price(internal)).to eq(10)
      expect(tier.price(external)).to eq(25)
    end
  end

  describe ".visible" do
    it "hides hidden tiers" do
      shown = create(:membership_tier, hidden: false)
      create(:membership_tier, hidden: true)
      expect(MembershipTier.visible).to contain_exactly(shown)
    end
  end

  it "refuses to be destroyed while it has memberships (restrict_with_error)" do
    tier = create(:membership_tier)
    create(:membership, membership_tier: tier)
    expect(tier.destroy).to be(false)
    expect(tier.errors[:base]).to be_present
    expect(MembershipTier.exists?(tier.id)).to be(true)
  end
end
