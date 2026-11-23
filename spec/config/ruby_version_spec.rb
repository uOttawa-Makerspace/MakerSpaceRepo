# frozen_string_literal: true

require "rails_helper"

# .ruby-version is the one place the Ruby version is set. The Gemfile reads it and CI's setup-ruby reads it;
# Docker cannot read a file inside FROM, so each Dockerfile repeats it as a build-arg default and this spec keeps
# those copies equal to it.
RSpec.describe "Ruby version" do
  let(:version) { Rails.root.join(".ruby-version").read.strip }

  %w[Dockerfile .devcontainer/Dockerfile].each do |path|
    it "#{path} builds on the Ruby version in .ruby-version" do
      expect(Rails.root.join(path).read[/^ARG RUBY_VERSION=(\S+)$/, 1]).to eq(version)
    end
  end

  it "is the version this process runs" do
    expect(RUBY_VERSION).to eq(version)
  end
end
