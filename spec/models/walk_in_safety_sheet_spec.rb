require "rails_helper"

RSpec.describe WalkInSafetySheet, type: :model do
  let(:user) { create(:user, :regular_user) }
  let(:space) { create(:space) }

  def build_sheet(*traits, **attrs)
    build(:walk_in_safety_sheet, *traits, { user: user, space: space }.merge(attrs))
  end

  it "has 6 agreements" do
    expect(WalkInSafetySheet::NUMBER_OF_AGREEMENTS).to eq(6)
  end

  describe "validations" do
    it "accepts a complete adult sheet" do
      expect(build_sheet(:is_adult, is_minor: false)).to be_valid
    end

    it "accepts a complete minor sheet" do
      expect(build_sheet(:is_minor)).to be_valid
    end

    it "requires is_minor to be true or false" do
      expect(build_sheet(:is_adult, is_minor: nil)).not_to be_valid
    end

    it "requires adult signature and home phone unless minor" do
      sheet = build_sheet(:is_adult, is_minor: false, participant_signature: "", participant_telephone_at_home: "")
      expect(sheet).not_to be_valid
      expect(sheet.errors.attribute_names).to include(:participant_signature, :participant_telephone_at_home)
    end

    it "requires guardian details for a minor" do
      sheet = build_sheet(:missing_minor_info)
      expect(sheet).not_to be_valid
      expect(sheet.errors.attribute_names).to include(:guardian_signature, :minor_participant_name,
                                                       :guardian_telephone_at_home, :guardian_telephone_at_work)
    end

    it "does not require adult fields for a minor nor guardian fields for an adult" do
      expect(build_sheet(:is_minor, participant_signature: nil)).to be_valid
      expect(build_sheet(:is_adult, is_minor: false, guardian_signature: nil)).to be_valid
    end

    it "always requires an emergency contact" do
      sheet = build_sheet(:is_adult, is_minor: false, emergency_contact_name: "", emergency_contact_telephone: "")
      expect(sheet).not_to be_valid
      expect(sheet.errors.attribute_names).to include(:emergency_contact_name, :emergency_contact_telephone)
    end

    it "allows one sheet per user per space" do
      build_sheet(:is_adult, is_minor: false).save!
      dup = build_sheet(:is_adult, is_minor: false)
      expect(dup).not_to be_valid
      expect(dup.errors[:space]).to include("has already been taken")
      other_user = build_sheet(:is_adult, is_minor: false, user: create(:user, :regular_user))
      expect(other_user).to be_valid
    end
  end

  describe "supervisor snapshot" do
    let(:space) { create(:space, :with_space_managers) }

    it "copies the space managers' names and emails when the sheet is created" do
      sheet = build_sheet(:is_adult, is_minor: false)
      expect(sheet.supervisor_names).to be_nil # after_initialize runs before the factory assigns the space
      sheet.save!
      managers = space.space_managers.pluck(:name, :email)
      expect(sheet.supervisor_names).to eq(managers.map(&:first).join(","))
      expect(sheet.supervisor_contacts).to eq(managers.map(&:last).join(","))
      expect(sheet.supervisor_information).to eq(managers)
    end

    it "keeps the snapshot after the space's managers change, and the columns are read-only" do
      sheet = build_sheet(:is_adult, is_minor: false)
      sheet.save!
      names = sheet.supervisor_names
      space.update!(space_managers: [create(:user, :admin)])
      sheet = WalkInSafetySheet.find(sheet.id)
      expect(sheet.supervisor_names).to eq(names)
      expect { sheet.update!(supervisor_names: "Someone Else") }.to raise_error(ActiveRecord::ReadonlyAttributeError)
      expect(sheet.reload.supervisor_names).to eq(names)
    end

    it "falls back to the Brunsfield Centre space when none is given" do
      brunsfield = Space.find_by(name: "Brunsfield Centre") || create(:space, name: "Brunsfield Centre")
      expect(WalkInSafetySheet.new.space).to eq(brunsfield)
      expect(WalkInSafetySheet.new(space: create(:space)).space).not_to eq(brunsfield)
    end

    it "leaves the space unset when no Brunsfield space exists" do
      Space.where(name: "Brunsfield Centre").destroy_all
      expect(WalkInSafetySheet.new.space).to be_nil
    end

    it "returns an empty list when no supervisors are stored" do
      expect(WalkInSafetySheet.new(supervisor_names: nil, supervisor_contacts: nil).supervisor_information).to eq([])
    end

    it "pairs names with contacts positionally and drops unmatched contacts" do
      sheet = WalkInSafetySheet.new(supervisor_names: "A,B", supervisor_contacts: "a@x")
      expect(sheet.supervisor_information).to eq([["A", "a@x"], ["B", nil]])
    end
  end
end
