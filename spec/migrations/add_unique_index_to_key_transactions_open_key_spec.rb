# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261106110000_add_unique_index_to_key_transactions_open_key")

# CREATE INDEX CONCURRENTLY cannot run in a transaction, so this spec runs outside the transactional wrapper.
# It drops the index to create duplicates, rebuilds it afterwards and removes the rows it made.
RSpec.describe AddUniqueIndexToKeyTransactionsOpenKey do
  self.use_transactional_tests = false

  let(:conn) { ActiveRecord::Base.connection }
  let(:index) { AddUniqueIndexToKeyTransactionsOpenKey::INDEX_NAME }
  let!(:space) { create(:space) }
  let!(:key) { create(:key, space_id: space.id) }
  let!(:user) { create(:user) }

  before { drop_index }

  after do
    KeyTransaction.where(key_id: key.id).delete_all
    key.destroy
    user.destroy
    space.destroy
    migrate(:up) unless found
  end

  def drop_index = conn.execute("DROP INDEX IF EXISTS #{index}")

  def found = conn.indexes(:key_transactions).find { |i| i.name == index }

  def migrate(direction = :up)
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(direction) }
  end

  def insert(return_date: nil, key_id: key.id)
    KeyTransaction.insert_all!([{ key_id: key_id, user_id: user.id, deposit_amount: 10, return_date: return_date,
                                  created_at: Time.current, updated_at: Time.current }]).rows.flatten.first
  end

  def rows = conn.select_rows("SELECT * FROM key_transactions WHERE key_id = #{key.id} ORDER BY id")

  it "refuses while a key has two open transactions, naming the ids, and changes nothing" do
    ids = [insert, insert]
    closed = insert(return_date: Date.current)
    before_rows = rows

    expect { migrate }.to raise_error(UniqueIndexGuard::DuplicatesFound, /key_id=#{key.id} -> ids #{ids.join(',')}\b/)

    expect(found).to be_nil
    expect(rows).to eq(before_rows)
    expect(rows.map(&:first)).to include(closed)
  end

  context "on clean data" do
    before do
      insert(return_date: 2.days.ago.to_date)
      insert(return_date: 1.day.ago.to_date)
      insert
      migrate
    end

    it "builds a valid, unique, partial index" do
      expect(found).to have_attributes(unique: true, columns: %w[key_id])
      expect(found).to be_valid
      expect(found.where).to include("return_date IS NULL")
    end

    it "refuses a second open transaction for the same key" do
      expect { insert }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "allows more closed transactions for the key, and an open one for another key" do
      expect { insert(return_date: Date.current) }.not_to raise_error
      other = create(:key, space_id: space.id)
      expect { insert(key_id: other.id) }.not_to raise_error
      KeyTransaction.where(key_id: other.id).delete_all
      other.destroy
    end

    it "lets a new transaction open once the previous one is returned" do
      KeyTransaction.not_returned.where(key_id: key.id).update_all(return_date: Date.current)
      expect { insert }.not_to raise_error
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

  describe "KeyTransaction" do
    before { migrate }

    it "refuses a second open transaction as an invalid record" do
      insert
      second = KeyTransaction.new(key: key, user: user, deposit_amount: 10)
      expect(second.save).to be(false)
      expect(second.errors[:key_id]).to include("already has an open transaction")
      expect { KeyTransaction.create!(key: key, user: user, deposit_amount: 10) }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end
end
