# frozen_string_literal: true

require "rails_helper"

# db/schema.rb has to carry the database's own functions and triggers, or a database built from it would lack them.
RSpec.describe SchemaDumperTriggers do
  let(:dump) do
    StringIO.new.tap { |stream| ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection_pool, stream) }.string
  end

  it "writes the ledger's append-only function and triggers after the tables, as SQL to run again" do
    function = dump.index("CREATE OR REPLACE FUNCTION public.payment_ledger_entries_append_only()")

    expect(function).to be > dump.index('create_table "payment_ledger_entries"')
    expect(dump).to include("  execute <<~'SQL'\n    CREATE TRIGGER payment_ledger_entries_no_change BEFORE DELETE OR UPDATE")
    expect(dump.index("CREATE TRIGGER payment_ledger_entries_no_truncate")).to be > function
    expect(dump).to end_with("  SQL\nend\n")
  end

  it "leaves out the functions extensions own" do
    expect(dump).not_to match(/FUNCTION public\.(similarity|unaccent)\(/)
  end

  it "matches the checked-in schema" do
    expect(File.read(Rails.root.join("db/schema.rb"))).to include(dump[dump.index("  execute <<~'SQL'\n    CREATE OR REPLACE FUNCTION")..])
  end
end
