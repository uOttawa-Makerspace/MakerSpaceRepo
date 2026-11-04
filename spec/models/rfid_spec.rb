require "rails_helper"

RSpec.describe Rfid, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:user).without_validating_presence }
    end
  end

  describe "Validations" do
    context "card_number" do
      it do
        should validate_presence_of(:card_number).with_message(
                 "Card number is required."
               )
      end
      it do
        should validate_uniqueness_of(:card_number).with_message(
                 "Card number is already in use."
               )
      end
    end
  end

  describe "unique index on card_number" do
    it "makes the database refuse a duplicate card number, even past the validation" do
      create(:rfid, card_number: "DUPLICATE-1")
      duplicate = build(:rfid, card_number: "DUPLICATE-1")
      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "is case-sensitive, like the validation" do
      create(:rfid, card_number: "case-card")
      expect(build(:rfid, card_number: "CASE-CARD")).to be_valid
      expect { create(:rfid, card_number: "CASE-CARD") }.not_to raise_error
    end

    it "allows any number of rows without a card number" do
      expect { 2.times { build(:rfid, card_number: nil).save!(validate: false) } }.not_to raise_error
    end
  end

  describe "Scopes" do
    before(:each) do
      3.times { create(:rfid, user: nil) }
      2.times { create(:rfid) }
    end

    context "#recent_unset" do
      it "should return rfid with nil users" do
        expect(Rfid.recent_unset.count).to eq(3)
      end
    end
  end

  describe ".link_to_user!" do
    let(:user) { create(:user, :regular_user) }

    it "creates and links a card no reader ever saw" do
      expect(Rfid.link_to_user!("brand-new-card", user)).to be_nil
      card = Rfid.find_by!(card_number: "brand-new-card")
      expect(card.user_id).to eq(user.id)
      expect(card.mac_address).to be_nil
    end

    it "links an existing unlinked card without touching its mac_address" do
      card = create(:rfid, user: nil, mac_address: "aa:aa:aa:aa:aa:aa")
      expect(Rfid.link_to_user!(card.card_number, user)).to be_nil
      expect(card.reload.user_id).to eq(user.id)
      expect(card.mac_address).to eq("aa:aa:aa:aa:aa:aa")
    end

    it "refuses a card held by another user with the reason, changing nothing" do
      holder = create(:user, :regular_user)
      card = create(:rfid, user: holder)
      expect(Rfid.link_to_user!(card.card_number, user)).to eq("is already linked to another user")
      expect(card.reload.user_id).to eq(holder.id)
    end

    it "refuses a user who already has a card with the reason, changing nothing" do
      create(:rfid, user: user)
      other = create(:rfid, user: nil)
      expect(Rfid.link_to_user!(other.card_number, user)).to eq("user already has a card; unlink it first")
      expect(other.reload.user_id).to be_nil
      expect(Rfid.where(card_number: "never-created")).to be_empty
      expect { Rfid.link_to_user!("never-created", user) }.not_to change(Rfid, :count)
    end
  end

  describe ".unlink_from_user!" do
    let(:space_a) { create(:space) }
    let(:space_b) { create(:space) }
    let!(:reader_a) { create(:pi_reader, space: space_a) }
    let!(:reader_a2) { create(:pi_reader, space: space_a) }
    let!(:reader_b) { create(:pi_reader, space: space_b) }
    let(:owner) { create(:user, :regular_user) }
    let!(:card) { create(:rfid, user: owner, mac_address: "aa:aa:aa:aa:aa:aa") }
    let(:actor) { create(:user, :staff, space: space_a) }

    it "unlinks the card and re-homes it to the first reader of the actor's assigned space" do
      expect(Rfid.unlink_from_user!(owner, actor: actor)).to eq(1)
      card.reload
      expect(card.user_id).to be_nil
      expect(card.mac_address).to eq(reader_a.pi_mac_address)
    end

    it "uses the assigned space, not the space of the actor's last lab session" do
      create(:lab_session, user: actor, space: space_b, sign_in_time: 1.hour.ago, sign_out_time: 1.hour.from_now)
      Rfid.unlink_from_user!(owner, actor: actor)
      expect(card.reload.mac_address).to eq(reader_a.pi_mac_address)
    end

    it "lists the unlinked card for the actor's space afterwards" do
      Rfid.unlink_from_user!(owner, actor: actor)
      macs = PiReader.where(space: actor.space).pluck(:pi_mac_address)
      expect(Rfid.recent_unset.where(mac_address: macs)).to include(card)
    end

    it "keeps the card's mac_address when the actor has no assigned space" do
      actor.update_columns(space_id: nil)
      Rfid.unlink_from_user!(owner, actor: actor.reload)
      card.reload
      expect(card.user_id).to be_nil
      expect(card.mac_address).to eq("aa:aa:aa:aa:aa:aa")
    end

    it "keeps the card's mac_address when the assigned space has no reader" do
      actor.update!(space: create(:space))
      Rfid.unlink_from_user!(owner, actor: actor)
      expect(card.reload.mac_address).to eq("aa:aa:aa:aa:aa:aa")
    end

    it "is a no-op returning 0 for a user without a card" do
      other = create(:user, :regular_user)
      expect(Rfid.unlink_from_user!(other, actor: actor)).to eq(0)
      expect(card.reload.user_id).to eq(owner.id)
    end
  end

  describe ".unlink_card!" do
    let(:space) { create(:space) }
    let!(:reader) { create(:pi_reader, space: space) }
    let(:owner) { create(:user, :regular_user) }
    let(:actor) { create(:user, :staff, space: space) }
    let!(:card) { create(:rfid, user: owner, mac_address: "aa:aa:aa:aa:aa:aa") }

    it "unlinks and re-homes only the given card" do
      second = create(:rfid, user: owner, mac_address: "cc:cc:cc:cc:cc:cc")
      expect(Rfid.unlink_card!(card.card_number, actor: actor)).to eq(:unlinked)
      expect(card.reload.user_id).to be_nil
      expect(card.mac_address).to eq(reader.pi_mac_address)
      expect(second.reload.user_id).to eq(owner.id)
      expect(second.mac_address).to eq("cc:cc:cc:cc:cc:cc")
    end

    it "keeps mac_address for an actor without an assigned space" do
      actor.update_columns(space_id: nil)
      expect(Rfid.unlink_card!(card.card_number, actor: actor.reload)).to eq(:unlinked)
      expect(card.reload.mac_address).to eq("aa:aa:aa:aa:aa:aa")
    end

    it "reports an already unlinked card and changes nothing" do
      loose = create(:rfid, user: nil, mac_address: "bb:bb:bb:bb:bb:bb")
      expect(Rfid.unlink_card!(loose.card_number, actor: actor)).to eq(:already_unlinked)
      expect(loose.reload.mac_address).to eq("bb:bb:bb:bb:bb:bb")
    end

    it "reports an unknown card" do
      expect(Rfid.unlink_card!("no-such-card", actor: actor)).to eq(:not_found)
    end
  end
end
