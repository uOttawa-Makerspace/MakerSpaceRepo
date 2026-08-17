require "rails_helper"

RSpec.describe ExternalContact, type: :model do
  describe "validations" do
    it "requires first_name, last_name, and email" do
      contact = ExternalContact.new
      expect(contact).not_to be_valid
      expect(contact.errors[:first_name]).to be_present
      expect(contact.errors[:last_name]).to be_present
      expect(contact.errors[:email]).to be_present
    end

    it "rejects duplicate emails case-insensitively" do
      create(:external_contact, email: "jane@example.com")
      duplicate = build(:external_contact, email: "JANE@example.com")
      expect(duplicate).not_to be_valid
    end
  end

  describe "normalizes" do
    it "downcases and strips email" do
      contact = create(:external_contact, email: "  Jane@EXAMPLE.com  ")
      expect(contact.email).to eq("jane@example.com")
    end
  end

  describe ".find_or_create_by_details" do
    it "creates a new contact when none exists" do
      expect {
        ExternalContact.find_or_create_by_details(
          first_name: "Jane", last_name: "Doe", email: "jane@example.com", phone: "6135551234"
        )
      }.to change(ExternalContact, :count).by(1)
    end

    it "refreshes stale attributes on existing contact" do
      existing = create(:external_contact, email: "jane@example.com", phone: "000-000-0000")
      contact = ExternalContact.find_or_create_by_details(
        first_name: "Jane", last_name: "Doe", email: "jane@example.com", phone: "613-555-1234"
      )
      expect(contact.id).to eq(existing.id)
      expect(contact.phone).to eq("613-555-1234")
    end
  end

  describe "deletion safety" do
    it "prevents hard-destroying a contact who currently holds a key" do
      space = create(:space)
      contact = create(:external_contact)
      key = create(:key, :inventory_status, space_id: space.id)
      key.update!(holder: contact, status: :held, supervisor_id: create(:user, :admin).id)
      expect { contact.destroy }.not_to change(ExternalContact, :count)
      expect(contact.errors[:base]).to include("Cannot delete record because dependent keys exist")
    end

    it "allows hard-destroying a contact with no current keys" do
      contact = create(:external_contact)
      expect { contact.destroy }.to change(ExternalContact, :count).by(-1)
    end
  end

  describe "#soft_delete!" do
    it "marks the contact as deleted instead of removing the row" do
      contact = create(:external_contact)
      expect(contact.soft_delete!).to be true
      expect(contact.reload.deleted).to be true
    end

    it "refuses to soft delete a contact who currently holds a key" do
      space = create(:space)
      contact = create(:external_contact)
      key = create(:key, :inventory_status, space_id: space.id)
      key.update!(holder: contact, status: :held, supervisor_id: create(:user, :admin).id)
      expect(contact.soft_delete!).to be false
      expect(contact.reload.deleted).to be false
    end
  end
end