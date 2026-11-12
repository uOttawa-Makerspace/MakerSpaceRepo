# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261112200100_add_unique_index_to_paid_memberships_user_tier_and_end_date")

# CREATE INDEX CONCURRENTLY cannot run in a transaction, so this spec runs outside the transactional wrapper.
# It drops the index to create duplicates, rebuilds it afterwards and removes the rows it made.
RSpec.describe AddUniqueIndexToPaidMembershipsUserTierAndEndDate do
  self.use_transactional_tests = false

  let(:conn) { ActiveRecord::Base.connection }
  let(:index) { described_class::INDEX_NAME }
  let!(:user) { create(:user) }
  let!(:other_user) { create(:user) }
  let!(:tier) { create(:membership_tier) }
  let(:ends) { Time.zone.parse("2027-04-30 23:59:59") }

  before { conn.execute("DROP INDEX IF EXISTS #{index}") }

  after do
    Membership.where(user_id: [user.id, other_user.id]).delete_all
    tier.destroy
    user.destroy
    other_user.destroy
    migrate(:up) unless found
  end

  def found = conn.indexes(:memberships).find { |i| i.name == index }

  def migrate(direction = :up)
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(direction) }
  end

  def insert(status: "paid", end_date: ends, user_id: user.id)
    now = Time.current
    Membership.insert_all!([{ user_id: user_id, membership_tier_id: tier.id, status: status, start_date: now,
                              end_date: end_date, created_at: now, updated_at: now }]).rows.flatten.first
  end

  def rows = conn.select_rows("SELECT * FROM memberships WHERE user_id IN (#{user.id}, #{other_user.id}) ORDER BY id")

  it "refuses while a member holds two paid memberships of a tier ending together, naming the ids, and changes nothing" do
    ids = [insert, insert]
    insert(status: "revoked")
    before_rows = rows

    expect { migrate }.to raise_error(UniqueIndexGuard::DuplicatesFound, /user_id=#{user.id}, membership_tier_id=#{tier.id}, end_date=.* -> ids #{ids.join(",")}\b/)

    expect(found).to be_nil
    expect(rows).to eq(before_rows)
  end

  context "on clean data" do
    before do
      insert
      insert(status: "revoked")
      insert(status: "expired")
      insert(end_date: ends - 1.year)
      insert(user_id: other_user.id)
      migrate
    end

    it "builds a valid partial unique index for paid rows" do
      expect(found).to have_attributes(unique: true, columns: %w[user_id membership_tier_id end_date], where: "((status)::text = 'paid'::text)")
      expect(found).to be_valid
    end

    it "refuses a second paid membership with the same member, tier and end, and allows history rows" do
      expect { insert }.to raise_error(ActiveRecord::RecordNotUnique)
      expect { insert(status: "revoked") }.not_to raise_error
      expect { insert(status: "expired") }.not_to raise_error
      expect { insert(end_date: ends + 1.year) }.not_to raise_error
    end

    it "removes the index on down, keeping every row" do
      before_rows = rows
      migrate(:down)
      expect(found).to be_nil
      expect(rows).to eq(before_rows)
    end

    it "is safe to run again" do
      expect { migrate }.not_to raise_error
      expect(found).to be_valid
    end
  end
end
