# frozen_string_literal: true

require "rails_helper"

# Two migrations with the same version cannot both run: whichever loads second
# raises ActiveRecord::DuplicateMigrationVersionError (and schema_migrations
# could never record both). Slices are written in parallel worktrees, so this
# guard runs on the merged tree as well.
RSpec.describe "db/migrate versions" do
  let(:versions) { Dir[Rails.root.join("db/migrate/*.rb")].map { |f| File.basename(f)[/\A\d+/] } }

  it "are unique" do
    expect(versions.tally.select { |_, n| n > 1 }.keys).to eq([])
  end

  it "end at the version schema.rb records" do
    schema_version = File.read(Rails.root.join("db/schema.rb"))[/define\(version: ([\d_]+)\)/, 1].delete("_")
    expect(versions.max).to eq(schema_version)
  end

  it "keep the quote-integrity migration clear of the coupon slice's 20261030120000" do
    expect(Dir[Rails.root.join("db/migrate/*_add_quote_integrity_columns_to_job_orders.rb")].map { |f| File.basename(f)[/\A\d+/] })
      .to eq(["20261030130000"])
  end
end
