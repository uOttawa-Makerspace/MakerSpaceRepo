# frozen_string_literal: true

require "rails_helper"

RSpec.describe TranslationKeyScan do
  def keys(source, file = "app/views/users/tabs/_home.html.erb")
    items = described_class.calls(described_class.strip_comments(source), file)
    items.map { |item| item.respond_to?(:key) ? item.key : :skipped }
  end

  it "reads quoted and symbol keys, with or without parentheses" do
    source = %(<%= t("a.b") %> <%= t 'c.d' %> <%= I18n.t(:"e.f") %> <%= t(:g, count: 2) %>)
    expect(keys(source)).to eq(%w[a.b c.d e.f g])
  end

  it "resolves a lazy key in a view to the view's path" do
    expect(keys(%(<%= t(".title") %>))).to eq(["users.tabs.home.title"])
  end

  it "skips a key built at runtime, and a lazy key outside a view" do
    expect(keys(%(<%= t("a.\#{b}") %> <%= t(key) %>))).to eq(%i[skipped skipped])
    expect(keys(%(t(".title")), "app/controllers/users_controller.rb")).to eq([:skipped])
  end

  it "ignores comments, other methods and single-quoted text that looks like interpolation" do
    expect(keys(%(<%# t("x") %>\n  # t("y")\nformat("z") foo.t("w") it("v")))).to eq([])
    expect(keys(%(t('a.\#{b}')))).to eq(["a.\#{b}"])
  end

  it "names the attribute key of a model, in French only" do
    found, = described_class.calls(%(User.human_attribute_name(:email)), "app/views/x.html.erb")
    expect([found.key, found.locales]).to eq(["activerecord.attributes.user.email", [:fr]])
    expect(keys(%(human_attribute_name(:start_time)), "app/models/sub_space_booking.rb"))
      .to eq(["activerecord.attributes.sub_space_booking.start_time"])
    expect(keys(%(self.class.human_attribute_name(name)), "app/models/space.rb")).to eq([:skipped])
  end

  it "reports the line of each call" do
    items = described_class.calls(%(a\nb\n<%= t(key) %>), "app/views/x.html.erb")
    expect(items.map(&:location)).to eq(["app/views/x.html.erb:3"])
  end
end
