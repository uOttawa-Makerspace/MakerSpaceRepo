# frozen_string_literal: true

require "rails_helper"

# Production and staging keep Rails.cache (Solid Cache) in a database of its own, so
# the primary database, which is what the backups dump, carries no cache rows.
RSpec.describe "Solid Cache database" do
  def cache_config(env)
    Rails.application.config_for(Rails.root.join("config/cache.yml"), env: env)
  end

  {
    "production" => "makerspacerepo_cache",
    "staging" => "makerspacerepo_cache_staging"
  }.each do |env, name|
    it "stores the #{env} cache in the #{name} database" do
      expect(cache_config(env)).to include(database: "cache")

      db = ActiveRecord::Base.configurations.configs_for(env_name: env, name: "cache")
      primary = ActiveRecord::Base.configurations.configs_for(env_name: env, name: "primary")
      expect(db.database).to eq(name)
      expect(db.database).not_to eq(primary.database)
      expect(db.configuration_hash.except(:database, :migrations_paths)).to eq(
        primary.configuration_hash.except(:database)
      )
      expect(db.schema_dump).to eq("cache_schema.rb")
    end
  end

  it "uses no cache database in development and test" do
    %w[development test].each do |env|
      expect(cache_config(env)).not_to have_key(:database)
      expect(ActiveRecord::Base.configurations.configs_for(env_name: env, name: "cache")).to be_nil
    end
  end
end
