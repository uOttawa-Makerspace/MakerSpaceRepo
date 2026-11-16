# frozen_string_literal: true

require "rails_helper"

# db/schema.rb has to carry the database's own functions and triggers, or a database built from it would lack them.
RSpec.describe SchemaDumperTriggers do
  let(:connection) { ActiveRecord::Base.connection }
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

  it "leaves out the functions extensions own, and aggregates" do
    connection.execute("CREATE AGGREGATE schema_dumper_spec_sum (integer) (SFUNC = int4pl, STYPE = integer)")

    expect(dump).not_to match(/FUNCTION public\.(similarity|unaccent)\(/)
    expect(dump).not_to include("schema_dumper_spec_sum")
  end

  it "orders overloads of one function by their argument types" do
    %w[text integer].each do |type|
      connection.execute("CREATE FUNCTION schema_dumper_spec_f(#{type}) RETURNS integer LANGUAGE sql AS 'SELECT 1'")
    end

    expect(dump.index("schema_dumper_spec_f(integer)")).to be < dump.index("schema_dumper_spec_f(text)")
  end

  it "matches the checked-in schema, function and trigger SQL included" do
    schema = File.read(Rails.root.join("db/schema.rb"))
    definitions = connection.select_values(<<~SQL.squish)
      SELECT pg_get_functiondef('payment_ledger_entries_append_only()'::regprocedure)
      UNION ALL
      SELECT pg_get_triggerdef(oid) FROM pg_trigger WHERE tgrelid = 'payment_ledger_entries'::regclass AND NOT tgisinternal
    SQL

    expect(definitions.size).to eq(3)
    definitions.each { |sql| expect(schema).to include(sql.strip.gsub(/^(?=.)/, "    ")) }
    expect(schema).to include(dump[dump.index("  execute <<~'SQL'\n    CREATE OR REPLACE FUNCTION")..])
  end
end
