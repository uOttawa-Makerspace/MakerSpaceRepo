# frozen_string_literal: true

require "rails_helper"

RSpec.describe "users.deleted" do
  let(:column) { User.columns_hash.fetch("deleted") }

  it "is NOT NULL and defaults to false, so every `deleted = false` query sees every row" do
    expect(column.null).to be(false)
    expect(User.new.deleted).to be(false)
  end

  it "refuses a NULL at the database" do
    user = create(:user)
    expect { user.update_column(:deleted, nil) }.to raise_error(ActiveRecord::NotNullViolation)
  end

  describe "history of a soft-deleted user" do
    let(:user) { create(:user) }
    let(:space) { create(:space) }

    it "including_deleted reaches soft-deleted users that the default scope hides" do
      user.soft_delete!
      expect(User.find_by(id: user.id)).to be_nil
      expect(User.including_deleted.find(user.id)).to eq(user)
    end

    it "keeps the lab sessions and certifications of a soft-deleted user, and restore keeps them" do
      session = create(:lab_session, user: user, space: space, sign_in_time: 2.days.ago, sign_out_time: 2.days.ago + 1.hour)
      cert = create(:certification, :basic_training, user_id: user.id)
      user.soft_delete!
      expect(LabSession.where(user_id: user.id)).to contain_exactly(session)
      expect(Certification.where(user_id: user.id)).to contain_exactly(cert)
      user.restore!
      expect(User.find(user.id).lab_sessions).to contain_exactly(session)
      expect(User.find(user.id).certifications).to contain_exactly(cert)
    end

    it "their lab sessions and certifications still reach the user, and join to it" do
      session = create(:lab_session, user: user, space: space)
      cert = create(:certification, :basic_training, user_id: user.id)
      user.soft_delete!
      expect(LabSession.find(session.id).user).to eq(user)
      expect(Certification.find(cert.id).user).to eq(user)
      expect(LabSession.joins(:user)).to include(session)
      expect(Certification.joins(:user)).to include(cert)
    end

    it "a hard delete of a user is refused while visit or certification rows point at it" do
      create(:lab_session, user: user, space: space)
      expect { user.destroy }.to raise_error(ActiveRecord::InvalidForeignKey)
      expect(LabSession.where(user_id: user.id)).to exist
    end

    it "does not destroy certifications with the user either" do
      create(:certification, :basic_training, user_id: user.id)
      expect { user.destroy }.to raise_error(ActiveRecord::InvalidForeignKey)
      expect(Certification.where(user_id: user.id)).to exist
    end
  end
end
