# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261112190000_add_unique_index_to_cc_money_task_awards")

# CREATE INDEX CONCURRENTLY cannot run in a transaction, so this spec runs outside the transactional wrapper.
# It drops the index and the column to build old double awards, then restores both and removes its rows.
RSpec.describe AddUniqueIndexToCcMoneyTaskAwards do
  self.use_transactional_tests = false

  let(:conn) { ActiveRecord::Base.connection }
  let(:index) { described_class::INDEX_NAME }
  let!(:user) { create(:user) }
  let!(:task) { create(:volunteer_task) }
  let(:old) { Time.zone.parse("2026-03-04 10:00") }

  before do
    conn.execute("DROP INDEX IF EXISTS #{index}")
    CcMoney.reset_column_information
  end

  after do
    CcMoney.where(user_id: user.id).delete_all
    task.destroy
    Space.where(id: task.space_id).delete_all
    user.destroy
    migrate(:up) unless found
    CcMoney.reset_column_information
  end

  def found = conn.indexes(:cc_moneys).find { |i| i.name == index }

  def migrate(direction = :up)
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(direction) }
    PooledStatements.reset
  end

  def insert(cc: 5, created_at: old, user_id: user.id, volunteer_task_id: task.id)
    CcMoney.insert_all!([{ user_id: user_id, volunteer_task_id: volunteer_task_id, cc: cc,
                           created_at: created_at, updated_at: created_at }]).rows.flatten.first
  end

  def rows
    conn.select_rows("SELECT id, user_id, volunteer_task_id, cc, created_at FROM cc_moneys " \
                     "WHERE user_id = #{user.id} ORDER BY id")
  end
  def flagged = CcMoney.where(user_id: user.id, legacy_duplicate: true).order(:id).pluck(:id)

  context "with old double awards" do
    let!(:ids) { [insert(cc: 5), insert(cc: 7), insert(cc: 9)] }
    let!(:other_task) { create(:volunteer_task) }
    let!(:single) { insert(cc: 4, volunteer_task_id: other_task.id) }
    let!(:plain) { [insert(volunteer_task_id: nil), insert(volunteer_task_id: nil)] }

    after do
      CcMoney.where(user_id: user.id).delete_all
      other_task.destroy
      Space.where(id: other_task.space_id).delete_all
    end

    it "flags every award after the first of each pair and changes no row, amount or total" do
      before_rows = rows
      before_total = CcMoney.where(user_id: user.id).sum(:cc)

      migrate

      expect(flagged).to eq(ids.drop(1))
      expect(rows).to eq(before_rows)
      expect(CcMoney.where(user_id: user.id).sum(:cc)).to eq(before_total)
    end

    it "builds a valid unique index that still refuses a new award for the pair but allows other awards" do
      migrate

      expect(found).to have_attributes(unique: true,
                                       where: "((volunteer_task_id IS NOT NULL) AND (NOT legacy_duplicate))")
      expect(found).to be_valid
      expect { insert(created_at: Time.current) }.to raise_error(ActiveRecord::RecordNotUnique)
      expect { insert(volunteer_task_id: nil, created_at: Time.current) }.not_to raise_error
      other = create(:user)
      expect { insert(user_id: other.id, created_at: Time.current) }.not_to raise_error
      CcMoney.where(user_id: other.id).delete_all
      other.destroy
    end

    it "is safe to run twice" do
      migrate
      before_rows = rows
      expect { migrate }.not_to raise_error
      expect(flagged).to eq(ids.drop(1))
      expect(rows).to eq(before_rows)
    end

    it "removes the index and the column on down, keeping every row exactly" do
      before_rows = rows
      migrate
      migrate(:down)

      expect(found).to be_nil
      expect(conn.column_exists?(:cc_moneys, :legacy_duplicate)).to be(false)
      expect(rows).to eq(before_rows)
      migrate
      expect(flagged).to eq(ids.drop(1))
    end
  end

  it "stops, flagging and changing nothing, when a duplicate award was created after the migration began" do
    insert
    later = insert(created_at: 1.hour.from_now)
    before_rows = rows

    expect { migrate }.to raise_error(described_class::RecentDuplicateAward, /#{later}\b/)

    expect(found).to be_nil
    expect(rows).to eq(before_rows)
    expect(flagged).to be_empty
  end

  # Adding the column back puts it last, which changes the row type of SELECT cc_moneys.*. A plan another
  # pooled connection prepared before that must not survive into a later example's transaction.
  it "leaves no other pooled connection with a prepared plan for the old row shape" do
    migrate
    migrate(:down)
    other = ActiveRecord::Base.connection_pool.checkout
    select_awards = lambda do
      other.select_all("SELECT cc_moneys.* FROM cc_moneys WHERE user_id = $1", "awards", [user.id], preparable: true)
    end
    select_awards.call

    migrate

    expect { other.transaction { select_awards.call } }.not_to raise_error
  ensure
    ActiveRecord::Base.connection_pool.checkin(other) if other
  end

  it "builds the index on clean data without flagging anything" do
    insert
    migrate

    expect(flagged).to be_empty
    expect(found).to be_valid
  end
end
