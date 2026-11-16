# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261112130000_create_counter_recount_corrections")

# Additive: the archive table is created, down drops that table and nothing else.
RSpec.describe CreateCounterRecountCorrections do
  let(:connection) { ActiveRecord::Base.connection }

  # The schema already has the table; the migration creates it.
  before { connection.drop_table(:counter_recount_corrections) }

  def migrate(direction)
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(direction) }
  end

  it "creates the table with its constraints on up and leaves the counted tables alone" do
    repo = create(:repository)
    repo.update_column(:like, 5)

    migrate(:up)

    expect(connection.table_exists?(:counter_recount_corrections)).to be(true)
    expect(connection.columns(:counter_recount_corrections).reject(&:null).map(&:name))
      .to include("table_name", "row_id", "column_name", "new_value", "run_at")
    expect(repo.reload.like).to eq(5)
  end

  it "drops only the new table on down" do
    migrate(:up)
    repos = Repository.count

    migrate(:down)

    expect(connection.table_exists?(:counter_recount_corrections)).to be(false)
    expect(Repository.count).to eq(repos)
  end
end
