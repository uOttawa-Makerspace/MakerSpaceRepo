# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageCrawl::Browser do
  describe ".view_key" do
    def gem_spec(name, path) = instance_double(Gem::Specification, name:, full_gem_path: path)

    it "keys an app view by its path under app/views" do
      path = Rails.root.join("app/views/faqs/index.html.erb").to_s
      expect(described_class.view_key(path)).to eq("faqs/index.html.erb")
    end

    it "keys a view elsewhere in the app by its path under the app root" do
      path = Rails.root.join("app/components/card.html.erb").to_s
      expect(described_class.view_key(path)).to eq("app/components/card.html.erb")
    end

    it "keys a view inside a gem installed outside the app by the gem name" do
      gem_path = "/usr/local/bundle/gems/kaminari-1.2.2"
      allow(Gem).to receive(:loaded_specs).and_return("kaminari" => gem_spec("kaminari", gem_path))

      expect(described_class.view_key("#{gem_path}/app/views/kaminari/_page.html.erb"))
        .to eq("kaminari:app/views/kaminari/_page.html.erb")
    end

    it "keys a view inside a gem installed under the app root (vendor/bundle) by the gem name" do
      gem_path = Rails.root.join("vendor/bundle/ruby/4.0.0/gems/kaminari-1.2.2").to_s
      allow(Gem).to receive(:loaded_specs).and_return("kaminari" => gem_spec("kaminari", gem_path))

      expect(described_class.view_key("#{gem_path}/app/views/kaminari/_page.html.erb"))
        .to eq("kaminari:app/views/kaminari/_page.html.erb")
    end

    it "keys a view inside the bundle path by its path there when no loaded gem holds it" do
      bundle = Rails.root.join("vendor/bundle/ruby/4.0.0")
      allow(Gem).to receive(:loaded_specs).and_return({})
      allow(Bundler).to receive(:bundle_path).and_return(bundle)

      expect(described_class.view_key("#{bundle}/gems/other-2.0/app/views/x.html.erb"))
        .to eq("bundle:gems/other-2.0/app/views/x.html.erb")
    end

    it "refuses a view outside the app and its gems" do
      allow(Gem).to receive(:loaded_specs).and_return({})

      expect { described_class.view_key("/opt/views/x.html.erb") }
        .to raise_error(ArgumentError, %r{/opt/views/x\.html\.erb})
    end
  end
end
