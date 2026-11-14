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

  describe ".supervisor_options" do
    it "lists each manager once as [name, id], sorted by name ignoring case" do
      bob = create(:user, :admin, name: "Bob Manager")
      alice = create(:user, :admin, name: "alice Manager")
      SpaceManagerJoin.create!(space: space, user: bob)
      SpaceManagerJoin.create!(space: create(:space), user: bob)
      SpaceManagerJoin.create!(space: space, user: alice)

      expect(SpaceManagerJoin.supervisor_options).to eq([["alice Manager", alice.id], ["Bob Manager", bob.id]])
    end

    it "is empty when no space has a manager" do
      expect(SpaceManagerJoin.supervisor_options).to eq([])
    end
  end
end
