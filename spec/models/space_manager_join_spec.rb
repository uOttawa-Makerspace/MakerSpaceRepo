# frozen_string_literal: true

require "rails_helper"

RSpec.describe SpaceManagerJoin, type: :model do
  let(:space) { create(:space) }

  it "accepts admins only" do
    expect(SpaceManagerJoin.new(space: space, user: create(:user, :admin))).to be_valid
    join = SpaceManagerJoin.new(space: space, user: create(:user, :staff))
    expect(join).not_to be_valid
    expect(join.errors[:base]).to eq(["User must be an admin"])
  end

  it "allows a manager once per space" do
    admin = create(:user, :admin)
    SpaceManagerJoin.create!(space: space, user: admin)
    expect(SpaceManagerJoin.new(space: space, user: admin)).not_to be_valid
    expect(SpaceManagerJoin.new(space: create(:space), user: admin)).to be_valid
  end

  it "skips the admin check when no user is set" do
    expect(SpaceManagerJoin.new(space: space)).to be_valid
  end
end
