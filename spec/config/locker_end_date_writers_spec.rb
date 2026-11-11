# frozen_string_literal: true

require "rails_helper"

# Moving a rental's end date later has to clear its expiry notice, which LockerRental#assign_owned_until and
# #extend_until do. This lists every place in app/ and lib/ that writes the column, so a new writer is noticed.
module LockerEndDateWriters
  ASSIGNMENT = /owned_until\s*(\|\|)?=(?![=~>])/
  MASS_UPDATE = /(update|update!|update_all|update_columns|update_column|assign_attributes)\b[^\n]*\bowned_until\b/
  WRITE = Regexp.union(ASSIGNMENT, MASS_UPDATE)

  # Files allowed to write the column, with why. The model's own methods are the notice-resetting writers; the
  # create action sets the date of a rental that is not saved yet, which has no notice to clear.
  ALLOWED = {
    "app/models/locker_rental.rb" => "the notice-resetting writers",
    "app/controllers/locker_rentals_controller.rb" => "create action on an unsaved rental"
  }.freeze
end

RSpec.describe "Writers of locker_rentals.owned_until" do
  let(:writers) do
    Dir[Rails.root.join("{app,lib}/**/*.{rb,rake}").to_s].select { |path| File.read(path).match?(LockerEndDateWriters::WRITE) }
      .map { |path| Pathname(path).relative_path_from(Rails.root).to_s }
  end

  it "are only the files that reset the expiry notice or create a new rental" do
    expect(writers.sort).to eq(LockerEndDateWriters::ALLOWED.keys.sort)
  end

  it "keeps the controller's direct assignments inside the create action" do
    source = File.read(Rails.root.join("app/controllers/locker_rentals_controller.rb"))
    direct = source.lines.each_index.select { |i| source.lines[i].match?(/@locker_rental\.owned_until\s*(\|\|)?=/) }
    create_start = source.lines.index { |l| l.match?(/^\s*def create\b/) }
    create_end = source.lines.each_index.find { |i| i > create_start && source.lines[i].match?(/^  end\b/) }

    expect(direct).to all(be_between(create_start, create_end))
  end
end
