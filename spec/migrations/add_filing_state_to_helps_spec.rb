require "rails_helper"
require Rails.root.join("db/migrate/20261115120000_add_filing_state_to_helps")

# DDL is transactional in the test database, so each example takes the columns off first and the rollback restores
# the real schema afterwards.
RSpec.describe AddFilingStateToHelps do
  let(:connection) { ActiveRecord::Base.connection }
  let(:created) { Time.zone.parse("2026-03-11 19:37:48") }
  let(:touched) { Time.zone.parse("2026-03-12 08:00:00") }

  def migrate(direction)
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(direction) }
    Help.reset_column_information
  end

  def legacy_row(number)
    connection.select_value(<<~SQL.squish)
      INSERT INTO helps (gh_issue_number, created_at, updated_at)
      VALUES (#{connection.quote(number)}, #{connection.quote(created)}, #{connection.quote(touched)}) RETURNING id
    SQL
  end

  def columns = connection.columns(:helps).map(&:name)

  before { migrate(:down) }

  after { Help.reset_column_information }

  it "marks every existing row filed and mailed at its creation, and changes nothing else" do
    filed = legacy_row("17")
    failed = legacy_row(nil)
    migrate(:up)

    [filed, failed].each do |id|
      expect(Help.find(id)).to have_attributes(created_at: created, updated_at: touched, filed_at: created,
                                               mailed_at: created, resends: 0, source: nil)
    end
    expect(Help.find(filed).gh_issue_number).to eq("17")
    expect(Help.find(failed).gh_issue_number).to be_nil
    expect(Help.unfinished).to be_empty
  end

  it "rolls back to the original columns, keeping every row and its issue number, and runs again" do
    id = legacy_row("17")
    migrate(:up)
    migrate(:down)

    expect(columns).to contain_exactly("id", "gh_issue_number", "created_at", "updated_at")
    expect(connection.select_rows("SELECT gh_issue_number FROM helps WHERE id = #{id}")).to eq([["17"]])
    expect(connection.foreign_keys(:helps)).to be_empty
    migrate(:up)
    expect(columns).to include("user_id", "filed_at", "mailed_at", "resends")
    expect(connection.foreign_keys(:helps).map(&:to_table)).to eq(["users"])
  end
end
