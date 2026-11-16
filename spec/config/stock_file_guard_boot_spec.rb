# frozen_string_literal: true

require "rails_helper"
require "open3"

# The Docker image build boots the app without credentials to precompile assets. Loading ActiveStorage::Blob sets
# up the storage service, and the S3 service needs credentials, so booting must leave Blob unloaded until it is used.
RSpec.describe "Stock file guard initializer" do
  it "leaves ActiveStorage::Blob unloaded when the app boots without eager loading" do
    script = 'print(ActiveStorage.autoload?(:Blob) ? "unloaded" : "loaded")'
    out, status = Open3.capture2e({ "CI" => nil, "COVERAGE" => nil }, "bin/rails", "runner", script,
                                  chdir: Rails.root.to_s)

    expect(status).to be_success, out
    expect(out.lines.last).to eq("unloaded")
  end

  it "still adds the blob checks once Blob loads" do
    expect(ActiveStorage::Blob.ancestors).to include(BlobOwners, HiddenRepositoryBlob, JobOrderBlob)
  end
end
