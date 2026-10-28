# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApiRefreshToken, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }

  describe ".issue!" do
    it "stores only the SHA-256 digest of a 32-byte token and exposes the raw value once" do
      token = described_class.issue!(user, user_agent: "Mozilla")
      raw = token.raw_token
      expect(Base64.urlsafe_decode64(raw).bytesize).to eq(32)
      expect(token.token_digest).to eq(Digest::SHA256.hexdigest(raw))
      expect(described_class.find(token.id).raw_token).to be_nil
      expect(token.token_digest).not_to include(raw)
      expect(token).to have_attributes(user_id: user.id, token_version: user.token_version, user_agent: "Mozilla")
      expect(token.family_id).to match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)
    end

    it "expires in 30 days" do
      now = Time.current
      expect(described_class.issue!(user, now: now).expires_at).to be_within(1.second).of(now + 30.days)
    end

    it "has a unique digest index" do
      token = described_class.issue!(user)
      expect { described_class.create!(token.attributes.except("id")) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe ".find_by_raw" do
    it "finds by digest" do
      token = described_class.issue!(user)
      expect(described_class.find_by_raw(token.raw_token)).to eq(token)
    end

    it "returns nil for blank, unknown and non-string input" do
      [nil, "", "nope", ["x"], { a: 1 }].each { |raw| expect(described_class.find_by_raw(raw)).to be_nil }
    end
  end

  # What the refresh endpoint does with a presented token: find, then rotate!.
  describe "presenting a token (find_by_raw + rotate!)" do
    def present(raw) = described_class.find_by_raw(raw)&.rotate!

    it "rotates a live token" do
      token = described_class.issue!(user)
      expect(present(token.raw_token)).to be_a(described_class)
    end

    it "refuses an expired token" do
      token = described_class.issue!(user, now: 31.days.ago)
      expect(present(token.raw_token)).to be_nil
    end

    it "refuses a revoked token without a successor, and does not touch the family" do
      first = described_class.issue!(user)
      sibling = described_class.issue!(user, family: first.family_id, family_expires_at: first.family_expires_at)
      first.update!(revoked_at: Time.current)
      expect(present(first.raw_token)).to be_nil
      expect(sibling.reload.revoked_at).to be_nil
    end

    it "refuses a stale token_version" do
      token = described_class.issue!(user)
      user.update_columns(token_version: user.token_version + 1)
      expect(present(token.raw_token)).to be_nil
    end

    it "refuses soft-deleted and inactive users" do
      token = described_class.issue!(user)
      user.update_columns(active: false)
      expect(present(token.raw_token)).to be_nil
      user.update_columns(active: true, deleted: true)
      expect(present(token.raw_token)).to be_nil
    end

    context "replay of an already rotated token" do
      include ActiveSupport::Testing::TimeHelpers

      let!(:first) { described_class.issue!(user) }
      let!(:second) { first.rotate! }
      let!(:other_family) { described_class.issue!(user) }

      it "within 30 seconds raises RefreshInProgress and revokes nothing" do
        travel_to(29.seconds.from_now) do
          expect { present(first.raw_token) }.to raise_error(described_class::RefreshInProgress)
        end
        expect(second.reload.revoked_at).to be_nil
        expect(described_class.find_by_raw(second.raw_token).rotate!).to be_present
      end

      it "after 30 seconds is theft: nil, and the whole family is revoked" do
        travel_to(31.seconds.from_now) do
          expect(present(first.raw_token)).to be_nil
        end
        expect(second.reload.revoked_at).to be_present
        expect(present(second.raw_token)).to be_nil
        expect(other_family.reload.revoked_at).to be_nil
      end

      it "inside the window but after the family was logged out is just refused (no 409)" do
        second.revoke_family!
        expect(present(first.raw_token)).to be_nil
      end
    end
  end

  describe "#rotate!" do
    it "revokes itself and issues a successor in the same family" do
      first = described_class.issue!(user)
      second = first.rotate!(user_agent: "UA")
      expect(first.reload).to have_attributes(replaced_by_id: second.id)
      expect(first.revoked_at).to be_present
      expect(second.family_id).to eq(first.family_id)
      expect(second.raw_token).to be_present
      expect(second.raw_token).not_to eq(first.raw_token)
      expect(second.user_agent).to eq("UA")
      expect(described_class.find_by_raw(second.raw_token)).to eq(second)
    end

    it "slides the expiry but never past 90 days from the family's first login" do
      first = described_class.issue!(user, now: 80.days.ago)
      first.update!(expires_at: 10.days.from_now) # as if renewed by earlier rotations
      second = first.rotate!
      expect(second.expires_at).to be_within(1.second).of(first.family_expires_at)
      expect(second.family_expires_at).to eq(first.family_expires_at)
      expect(second.expires_at).to be < 11.days.from_now
    end

    it "sets the cap once, at the first login, and keeps it when older rows are pruned" do
      first = described_class.issue!(user, now: 80.days.ago)
      expect(first.family_expires_at).to be_within(1.second).of(first.created_at + 90.days)
      first.update!(expires_at: 10.days.from_now)
      second = first.rotate!
      described_class.where(id: first.id).delete_all # a prune removed the oldest row
      third = second.rotate!
      expect(third.family_expires_at).to eq(first.family_expires_at)
      expect(third.expires_at).to be <= first.family_expires_at
    end

    it "refuses to continue a family without its cap" do
      first = described_class.issue!(user)
      expect { described_class.issue!(user, family: first.family_id) }.to raise_error(ArgumentError)
    end

    it "slides by 30 days when the cap is far away" do
      first = described_class.issue!(user, now: 10.days.ago)
      expect(first.rotate!.expires_at).to be_within(2.seconds).of(30.days.from_now)
    end

    it "returns nil for a token past the family cap, even if its own expiry is later" do
      first = described_class.issue!(user, now: 100.days.ago)
      first.update!(expires_at: 5.days.from_now)
      expect(first.rotate!).to be_nil
    end

    it "returns nil for a revoked token without a successor" do
      first = described_class.issue!(user)
      first.update!(revoked_at: Time.current)
      expect(first.rotate!).to be_nil
    end

    it "treats a second rotation of the same token, after the grace window, as a replay and revokes the family" do
      first = described_class.issue!(user)
      stale = described_class.find(first.id)
      successor = first.rotate!
      travel_to(31.seconds.from_now) { expect(stale.rotate!).to be_nil }
      expect(successor.reload.revoked_at).to be_present
    end

    it "returns nil when the token_version moved on" do
      first = described_class.issue!(user)
      user.update_columns(token_version: 5)
      expect(first.rotate!).to be_nil
    end
  end

  describe "revocation helpers" do
    it ".revoke_family! revokes only that family's live tokens" do
      a = described_class.issue!(user)
      b = described_class.issue!(user, family: a.family_id, family_expires_at: a.family_expires_at)
      c = described_class.issue!(user)
      described_class.revoke_family!(a.family_id)
      expect([a, b, c].map { |t| t.reload.revoked_at.present? }).to eq([true, true, false])
    end

    it ".revoke_all_for! revokes every token of the user only" do
      mine = [described_class.issue!(user), described_class.issue!(user)]
      theirs = described_class.issue!(create(:user))
      described_class.revoke_all_for!(user.id)
      expect(mine.map { |t| t.reload.revoked_at }).to all(be_present)
      expect(theirs.reload.revoked_at).to be_nil
    end
  end

  describe "state changing between authenticate and rotate!" do
    let(:token) { described_class.issue!(user) }

    it "does not mint tokens when a password change lands in between (revoked by the change)" do
      found = described_class.find_by_raw(token.raw_token)
      found.user # association loaded and cached before the change
      User.find(user.id).store_new_password!("Brand-new-pw-123!")
      expect(found.rotate!).to be_nil
      expect(described_class.where(user_id: user.id).live).to be_empty
    end

    it "uses the CURRENT token_version even when nothing revoked the row (bump without revocation)" do
      found = described_class.find_by_raw(token.raw_token)
      found.user
      User.where(id: user.id).update_all("token_version = token_version + 1")
      expect(found.rotate!).to be_nil
      expect(described_class.where(user_id: user.id).count).to eq(1)
    end

    it "sees a deactivation that lands in between" do
      found = described_class.find_by_raw(token.raw_token)
      found.user
      User.where(id: user.id).update_all(active: false)
      expect(found.rotate!).to be_nil
    end
  end
end
