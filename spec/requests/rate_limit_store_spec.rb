# frozen_string_literal: true

require "rails_helper"

# Every rate_limit counts in RateLimitCounter (atomic across workers), never in
# the controller's cache_store (Solid Cache cannot count a fresh key atomically).
# The store is set once, by RateLimitStore, in the two controller bases.
RSpec.describe RateLimitStore do
  it "is the rate_limit every controller uses" do
    Rails.application.eager_load!
    controllers = (ActionController::Base.descendants + ActionController::API.descendants).select do |c|
      c.name && Object.const_source_location(c.name)&.first.to_s.start_with?(Rails.root.join("app/controllers").to_s)
    end
    expect(controllers).not_to be_empty
    expect(controllers.map { |c| c.method(:rate_limit).owner }.uniq).to eq([RateLimitStore::ClassMethods])
  end

  it "covers the two controller bases" do
    expect(ApplicationController.method(:rate_limit).owner).to eq(RateLimitStore::ClassMethods)
    expect(Api::V1::BaseController.method(:rate_limit).owner).to eq(RateLimitStore::ClassMethods)
  end

  it "refuses a call site that names its own store" do
    expect { Class.new(ApplicationController) { rate_limit to: 1, within: 1.minute, store: Rails.cache } }
      .to raise_error(ArgumentError, /store/)
  end

  it "has no other counter in app/ (no cache store increment)" do
    offenders = Dir[Rails.root.join("app/**/*.rb")].select do |file|
      File.read(file).match?(/(cache_store|Rails\.cache|cache)\.increment/)
    end
    expect(offenders).to be_empty
  end
end
