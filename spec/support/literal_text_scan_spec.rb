# frozen_string_literal: true

require "rails_helper"

RSpec.describe LiteralTextScan do
  def arguments(source) = described_class.literal_arguments(source)

  it "reports quoted words handed to a rendering helper" do
    expect(arguments(%(<%= link_to "Hello there", root_path %>))).to eq(["Hello there"])
    expect(arguments(%(<%= tag.p "Welcome" %>))).to eq(["Welcome"])
    expect(arguments(%(<%= link_to "<b>Hello</b>", root_path %>))).to eq(["<b>Hello</b>"])
    expect(arguments(%(<%= tag.p "<em>Welcome</em>" %>))).to eq(["<em>Welcome</em>"])
    expect(arguments(%(<%= link_to "Total\#{n}", root_path %>))).to eq(["Total\#{n}"])
    expect(arguments(%(<%= t("k", default: "Plain words") %>))).to eq(["Plain words"])
  end

  it "ignores urls, fragments, a lone interpolation, markup without text and shared names" do
    expect(arguments(%(<%= link_to "https://example.com", root_path %>))).to eq([])
    expect(arguments(%(<%= link_to "/path", root_path %>))).to eq([])
    expect(arguments(%(<%= link_to "#", root_path %>))).to eq([])
    expect(arguments(%(<%= link_to "\#{x}", root_path %>))).to eq([])
    expect(arguments(%(<%= link_to "<i class='icon'></i>", root_path %>))).to eq([])
    expect(arguments(%(<%= label_tag "sort_\#{sort}", t("x") %>))).to eq([])
    expect(arguments(%(<%= link_to "<i class=\\"fa\\"></i> \#{t('x')}".html_safe, root_path %>))).to eq([])
    expect(arguments(%(<%= link_to "<i class=\\"fa\\"></i> Hello", root_path %>))).to eq(["<i class=\\\"fa\\\"></i> Hello"])
    expect(arguments(%(<%= link_to "MakerRepo", root_path %>))).to eq([])
  end

  it "reports a literal attribute and visible words" do
    expect(described_class.literal_attributes(%(<img alt="A logo">))).to eq(["A logo"])
    expect(described_class.literal_attributes(%(<img alt="<%= t('x') %>">))).to eq([])
    expect(described_class.visible_literals("<p>Hello <%= name %></p>")).to eq(["Hello"])
    expect(described_class.visible_literals("<p><%= t('x') %></p>")).to eq([])
  end

  it "ignores a path shown as written but not words around it" do
    expect(described_class.visible_literals("<code>/learning_area/s/</code>")).to eq([])
    expect(described_class.visible_literals("<p>Go to /help now</p>")).to eq(%w[Go to now])
  end
end
