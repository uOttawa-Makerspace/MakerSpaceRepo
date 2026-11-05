# frozen_string_literal: true

require "rails_helper"

# reset_pk_sequence! is what fixtures and restore scripts rely on after rows are
# inserted with explicit ids; the sequence must continue after the highest id.
RSpec.describe "PostgreSQL reset_pk_sequence!" do
  let(:connection) { ActiveRecord::Base.connection }
  let(:table) { "pk_sequence_probe" }

  before do
    connection.create_table(table) { |t| t.string :name }
  end

  def next_id
    connection.insert("INSERT INTO #{table} (name) VALUES ('next')", nil, "id")
  end

  it "moves the sequence past the highest explicit id" do
    connection.execute("INSERT INTO #{table} (id, name) VALUES (5, 'a'), (41, 'b')")

    connection.reset_pk_sequence!(table)

    expect(next_id).to eq(42)
  end

  it "restarts the sequence at its minimum value for an empty table" do
    connection.execute("INSERT INTO #{table} (id, name) VALUES (7, 'a')")
    connection.execute("DELETE FROM #{table}")

    connection.reset_pk_sequence!(table)

    expect(next_id).to eq(1)
  end

  it "does nothing for a table without a primary key" do
    connection.create_table("#{table}_nopk", id: false) { |t| t.string :name }

    expect { connection.reset_pk_sequence!("#{table}_nopk") }.not_to raise_error
  end
end
