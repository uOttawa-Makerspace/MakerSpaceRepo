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

  it "requires a user and a space" do
    join = SpaceManagerJoin.new
    expect(join).not_to be_valid
    expect(join.errors.details).to include(user: [{ error: :blank }], space: [{ error: :blank }])
  end

  it "has the database refuse a row without a user or a space" do
    now = Time.current
    admin = create(:user, :admin)
    [{ user_id: nil, space_id: space.id }, { user_id: admin.id, space_id: nil }].each do |row|
      insert = proc { SpaceManagerJoin.insert_all!([row.merge(created_at: now, updated_at: now)]) }
      expect { SpaceManagerJoin.transaction(requires_new: true, &insert) }.to raise_error(ActiveRecord::NotNullViolation)
    end
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

    it "orders managers whose names differ only in case by id" do
      first = create(:user, :admin, name: "Bob Manager")
      second = create(:user, :admin, name: "bob manager")
      SpaceManagerJoin.create!(space: space, user: second)
      SpaceManagerJoin.create!(space: create(:space), user: first)

      expect(SpaceManagerJoin.supervisor_options).to eq([["Bob Manager", first.id], ["bob manager", second.id]])
    end

    it "is empty when no space has a manager" do
      expect(SpaceManagerJoin.supervisor_options).to eq([])
    end
  end
end
