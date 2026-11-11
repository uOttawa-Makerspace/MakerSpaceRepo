require "rails_helper"
require "open3"

# Rails loads every migration file with `load`. A migration that also `require`s another migration file used to
# run that file a second time, which printed "already initialized constant" warnings for its constants.
RSpec.describe "Loading the migration files" do
  it "prints no constant redefinition warning when the foreign key migrations are loaded in order" do
    script = <<~RUBY
      %w[20261104000004 20261104000005].each do |version|
        file = Dir[Rails.root.join("db/migrate/\#{version}_*.rb")].sole
        load file
      end
    RUBY

    _out, err, status = Open3.capture3({ "RAILS_ENV" => "test" }, "bin/rails", "runner", script, chdir: Rails.root.to_s)

    expect(status).to be_success
    expect(err).not_to include("already initialized constant")
  end
end
