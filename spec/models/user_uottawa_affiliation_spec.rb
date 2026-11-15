# frozen_string_literal: true

require "rails_helper"

RSpec.describe User::UottawaAffiliation do
  def member(**attrs)
    create(:user, identity: "community_member", email: "member#{SecureRandom.hex(3)}@example.com", **attrs)
  end

  # Stores the address as given, as an older row may hold it.
  def member_with_email(email, **attrs)
    member(**attrs).tap { |u| u.update_columns(email: email) }
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

    it "is accepted with a confirmed uOttawa email" do
      expect(member_with_email("prof@uottawa.ca").update(identity: "staff_member")).to be(true)
    end

    it "is accepted with a confirmed uOttawa email in capitals" do
      expect(member_with_email("PROF@UOTTAWA.CA").update(identity: "staff_member")).to be(true)
    end

    it "is refused when uottawa.ca is only the start of another domain" do
      expect(member_with_email("prof@uottawa.ca.evil.com").update(identity: "staff_member")).to be(false)
    end

    it "is refused for a subdomain of uottawa.ca" do
      expect(member_with_email("prof@eng.uottawa.ca").update(identity: "staff_member")).to be(false)
    end

    it "is refused for an address without an @" do
      expect(member_with_email("uottawa.ca").update(identity: "staff_member")).to be(false)
    end

    it "is refused with a uOttawa email the account has not confirmed" do
      user = member(email: "prof@uottawa.ca", confirmed: false)

      expect(user.update(identity: "staff_member")).to be(false)
    end

    it "is accepted on a new account with a uOttawa email, which must be confirmed before signing in" do
      expect(build(:user, identity: "staff_member", email: "new@uottawa.ca", confirmed: false)).to be_valid
    end

    it "is refused on a new account with an outside email" do
      expect(build(:user, identity: "staff_member", email: "new@example.com")).not_to be_valid
    end

    it "is refused with an outside email even when uOEng has a record with the same student number" do
      user = member(student_id: "1234567")
      UoengProfile.record!(user, { "emplid" => "1234567" }, source: "student_number")

      expect(user.update(identity: "grad", program: "X", faculty: "Engineering", year_of_study: 1)).to be(false)
      expect(user.errors.details[:identity]).to include(error: :needs_uottawa_proof)
    end

    it "is refused when switching between two internal identities without proof" do
      user = member(student_id: "1234567")
      user.update_columns(identity: "undergrad", program: "X", faculty: "Engineering")

      expect(user.update(identity: "grad")).to be(false)
      expect(user.reload.identity).to eq("undergrad")
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
    it "lists internal accounts without a confirmed uOttawa email, and agrees with the per-account check" do
      no_proof = member.tap { |u| u.update_columns(identity: "staff_member") }
      unconfirmed = member_with_email("a@uottawa.ca").tap { |u| u.update_columns(identity: "grad", confirmed: false) }
      lookalike = member_with_email("b@uottawa.ca.evil.com").tap { |u| u.update_columns(identity: "grad") }
      subdomain = member_with_email("c@eng.uottawa.ca").tap { |u| u.update_columns(identity: "grad") }
      with_uoeng = member(student_id: "3333333").tap { |u| u.update_columns(identity: "undergrad") }
      UoengProfile.record!(with_uoeng, { "emplid" => "3333333" }, source: "student_number")
      by_email = member_with_email("D@UOTTAWA.CA").tap { |u| u.update_columns(identity: "faculty_member") }
      external = member

      ids = User.internal_without_proof.pluck(:id)
      expect(ids).to contain_exactly(no_proof.id, unconfirmed.id, lookalike.id, subdomain.id, with_uoeng.id)
      [no_proof, unconfirmed, lookalike, subdomain, with_uoeng, by_email].each do |u|
        expect(ids.include?(u.id)).to eq(!u.reload.uottawa_affiliation_proven?)
      end
      expect(ids).not_to include(external.id)
    end
  end
end
