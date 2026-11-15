# frozen_string_literal: true

require "rails_helper"

RSpec.describe User::UottawaAffiliation do
  def member(**attrs)
    create(:user, identity: "community_member", email: "member#{SecureRandom.hex(3)}@example.com", **attrs)
  end

  def confirm_by_uoeng!(user, emplid)
    UoengProfile.record!(user, { "emplid" => emplid }, source: "student_number")
  end

  describe "choosing an internal identity" do
    it "is refused without proof, with a message in English and French" do
      user = member
      user.identity = "faculty_member"

      expect(user).not_to be_valid
      expect(user.errors.full_messages_for(:identity).first).to include("confirmed @uottawa.ca email address")
      I18n.with_locale(:fr) do
        user.valid?
        expect(user.errors.full_messages_for(:identity).first).to include("adresse courriel @uottawa.ca confirmée")
      end
    end

    it "is accepted with a confirmed uOttawa email, whatever its case" do
      user = member(email: "Prof@UOttawa.ca")
      user.update_columns(email: "Prof@UOttawa.ca")

      expect(user.update(identity: "staff_member")).to be(true)
    end

    it "is refused with a uOttawa email the account has not confirmed" do
      user = member(email: "prof@uottawa.ca", confirmed: false)

      expect(user.update(identity: "staff_member")).to be(false)
    end

    it "is accepted on a new account with a uOttawa email, which must be confirmed before signing in" do
      user = build(:user, identity: "staff_member", email: "new@uottawa.ca", confirmed: false)

      expect(user).to be_valid
    end

    it "is refused on a new account with an outside email" do
      user = build(:user, identity: "staff_member", email: "new@example.com")

      expect(user).not_to be_valid
    end

    it "is accepted with the student number uOEng confirmed" do
      user = member(student_id: "1234567")
      confirm_by_uoeng!(user, "1234567")

      expect(user.update(identity: "grad", program: "X", faculty: "Engineering", year_of_study: 1)).to be(true)
    end

    it "is refused when uOEng confirmed a different student number" do
      user = member(student_id: "1234567")
      confirm_by_uoeng!(user, "7654321")

      expect(user.update(identity: "grad", program: "X", faculty: "Engineering", year_of_study: 1)).to be(false)
      expect(user.errors.details[:identity]).to include(error: :needs_uottawa_proof)
    end

    it "is refused when the uOEng record has no student number" do
      user = member(student_id: "1234567")
      confirm_by_uoeng!(user, nil)

      expect(user.update(identity: "staff_member")).to be(false)
    end
  end

  it "does not check a change to an external identity" do
    user = member
    user.update_columns(identity: "staff_member")

    expect(user.update(identity: "community_member")).to be(true)
  end

  it "keeps an existing internal identity without proof when other fields change" do
    user = member
    user.update_columns(identity: "staff_member")

    expect(user.update(name: "Renamed")).to be(true)
  end

  describe ".internal_without_proof" do
    it "lists internal accounts with neither a confirmed uOttawa email nor a uOEng-confirmed student number" do
      no_proof = member.tap { |u| u.update_columns(identity: "staff_member") }
      unconfirmed = member(email: "a@uottawa.ca").tap { |u| u.update_columns(identity: "grad", confirmed: false) }
      mismatch = member(student_id: "1111111").tap { |u| u.update_columns(identity: "undergrad") }
      confirm_by_uoeng!(mismatch, "2222222")

      by_email = create(:user, identity: "faculty_member", email: "b@uottawa.ca")
      by_email.update_columns(email: "B@UOTTAWA.CA")
      by_uoeng = member(student_id: "3333333").tap { |u| u.update_columns(identity: "undergrad") }
      confirm_by_uoeng!(by_uoeng, "3333333")
      external = member

      ids = User.internal_without_proof.pluck(:id)
      expect(ids).to contain_exactly(no_proof.id, unconfirmed.id, mismatch.id)
      expect(ids).not_to include(by_email.id, by_uoeng.id, external.id)
    end

    it "agrees with the per-account check" do
      users = [member.tap { |u| u.update_columns(identity: "staff_member") },
               create(:user, identity: "faculty_member", email: "c@uottawa.ca")]

      listed = User.internal_without_proof.pluck(:id)
      users.each { |u| expect(listed.include?(u.id)).to eq(!u.reload.uottawa_affiliation_proven?) }
    end
  end
end
