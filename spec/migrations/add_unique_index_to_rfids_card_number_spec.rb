require "rails_helper"
require Rails.root.join("db/migrate/20261104130000_add_unique_index_to_rfids_card_number")

# Duplicates only exist where the unique index is missing, so the example drops it
# (DDL is transactional; the index is back after the rollback).
RSpec.describe AddUniqueIndexToRfidsCardNumber do
  let(:connection) { ActiveRecord::Base.connection }

  before { connection.remove_index(:rfids, name: "index_rfids_on_card_number") }

  def insert_card(number)
    Rfid.insert_all!([{ card_number: number, created_at: Time.current, updated_at: Time.current }])
  end

  def migrate(direction = :up)
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(direction) }
  end

  it "refuses to build the index while a card number is on more than one row, naming the count" do
    2.times { insert_card("DUP-1") }
    3.times { insert_card("DUP-2") }
    insert_card("UNIQUE-1")

    expect { migrate }.to raise_error(RuntimeError, /2 card numbers appear on more than one rfids row/)
    expect(connection.index_exists?(:rfids, :card_number, name: "index_rfids_on_card_number")).to be(false)
    expect(Rfid.where(card_number: "DUP-2").count).to eq(3)
  end
end
