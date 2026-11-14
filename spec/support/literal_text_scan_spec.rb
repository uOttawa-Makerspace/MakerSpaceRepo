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
    expect(arguments(%(<%= button_tag "Sign In", class: "btn" %>))).to eq(["Sign In"])
    expect(arguments(%(<%= select_tag :user, "", prompt: "Pick a user" %>))).to eq(["Pick a user"])
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

  it "ignores a submitted value or a label's field name, but not words in those places" do
    expect(arguments(%(<%= f.button name: "state", value: "await_payment" do %>))).to eq([])
    expect(arguments(%(<%= label_tag "assign_indefinite", t("x") %>))).to eq([])
    expect(arguments(%(<%= f.submit value: "Save changes" %>))).to eq(["Save changes"])
    expect(arguments(%(<%= label_tag "Indefinite" %>))).to eq(["Indefinite"])
    expect(arguments(%(<%= link_to "active", root_path %>))).to eq(["active"])
  end

  it "reports a literal attribute and visible words" do
    expect(described_class.literal_attributes(%(<img alt="A logo">))).to eq(["A logo"])
    expect(described_class.literal_attributes(%(<img alt="<%= t('x') %>">))).to eq([])
    expect(described_class.visible_literals("<p>Hello <%= name %></p>")).to eq(["Hello"])
    expect(described_class.visible_literals("<p><%= t('x') %></p>")).to eq([])
  end

  it "ignores a page's style sheet but not the words after it" do
    expect(described_class.visible_literals("<style>.colors { margin: 2rem auto; }</style><p>Hi</p>")).to eq(["Hi"])
  end

  it "ignores a path shown as written but not words around it" do
    expect(described_class.visible_literals("<code>/learning_area/s/</code>")).to eq([])
    expect(described_class.visible_literals("<p>Go to /help now</p>")).to eq(%w[Go to now])
  end

  it "reports form builder labels and buttons, button_tag text and select prompts" do
    expect(arguments(%(<%= f.label :joins, "Capacity", class: "x" %>))).to eq(["Capacity"])
    expect(arguments(%(<%= f.submit "Send", class: "btn" %>))).to eq(["Send"])
    expect(arguments(%(<%= button_tag "Save changes" %>))).to eq(["Save changes"])
    expect(arguments(%(<%= f.select :x, list, { prompt: "Choose one" } %>))).to eq(["Choose one"])
    expect(arguments(%(<%= f.label :title, class: "form-label" do %>))).to eq([])
    expect(arguments(%(<%= f.submit t('lockers.request_form.submit'), class: 'btn' %>))).to eq([])
  end

  it "reads past a > inside a quoted attribute and ignores lower-case form codes" do
    expect(described_class.visible_literals(%(<input data-action="input->search#filter"><p>Hi</p>))).to eq(["Hi"])
    expect(described_class.visible_literals(%(<!-- The user's list --><p>Hi</p>))).to eq(["Hi"])
    expect(described_class.literal_attributes(%(<option value="events">))).to eq([])
    expect(described_class.literal_attributes(%(<option value="training-card-">))).to eq([])
    expect(described_class.literal_attributes(%(<input type="submit" value="send now">))).to eq(["send now"])
    expect(described_class.literal_attributes(%(<input type="submit" value="Send">))).to eq(["Send"])
  end
end
