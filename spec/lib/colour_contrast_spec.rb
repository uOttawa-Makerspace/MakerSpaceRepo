require "rails_helper"

# Pins the WCAG AA contrast of the theme colours declared in the SCSS variable
# file: 4.5:1 for normal text, 3:1 for large text (bold and at least 14pt, or at
# least 18pt). White on the brand orange is large-text only, so the large-text
# rules that make it bold and big enough are pinned here too. Pure arithmetic,
# no browser.
RSpec.describe "Theme colour contrast" do
  def styles = Rails.root.join("app/javascript/stylesheets")

  def variables
    @variables ||=
      styles
        .join("shared/_variables.scss")
        .read
        .scan(/^\$([\w-]+):\s*(#\h{6});/)
        .to_h
  end

  def rgb(hex) = hex.delete("#").scan(/../).map { |c| c.hex / 255.0 }

  def luminance(hex)
    r, g, b = rgb(hex).map { |c| c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055)**2.4 }
    (0.2126 * r) + (0.7152 * g) + (0.0722 * b)
  end

  def ratio(fg, bg)
    hi, lo = [luminance(fg), luminance(bg)].sort.reverse
    (hi + 0.05) / (lo + 0.05)
  end

  # Bootstrap's shade-color(): mix with black.
  def shade(hex, percent)
    "#" + rgb(hex).map { |c| format("%02x", (c * 255 * (1 - (percent / 100.0))).round) }.join
  end

  {
    "white text on primary (buttons, badges, home tile hover), large text" => ["#ffffff", "primary", 3.0],
    "primary text on white (links, .text-primary)" => %w[primary-text #ffffff],
    "primary text on the dark theme page" => %w[primary-text-dark #212529],
    "primary text on the footer (black)" => %w[primary-text-dark #000000],
    "primary text on the dark navbar" => %w[primary-text-dark #000000],
    "secondary text on white" => %w[secondary #ffffff],
    "secondary text on the tertiary background" => %w[secondary tertiary],
    "white text on secondary (buttons, badges)" => %w[#ffffff secondary],
    "primary text on the dark theme raised surface" => %w[primary-text-dark #2b3035],
    "dark theme muted text on the page" => %w[secondary-text-dark #212529],
    "dark theme muted text on the raised surface" => %w[secondary-text-dark #2b3035],
  }.each do |name, (fg, bg, minimum)|
    minimum ||= 4.5
    it "#{name} is at least #{minimum}:1" do
      colour = ->(key) { key.start_with?("#") ? key : variables.fetch(key) }
      expect(ratio(colour.call(fg), colour.call(bg))).to be >= minimum
    end
  end

  it "keeps white text readable on the button hover and active shades of primary" do
    [15, 20].each { |amount| expect(ratio("#ffffff", shade(variables.fetch("primary"), amount))).to be >= 4.5 }
  end

  it "keeps white text on the volunteer button hover colour at large-text contrast" do
    amount = styles.join("volunteers.scss").read[/^\$ceed-orange-hover:\s*shade-color\(\$primary,\s*(\d+)%\);/, 1]
    expect(amount).to be_present
    expect(ratio("#ffffff", shade(variables.fetch("primary"), amount.to_i))).to be >= 3.0
  end

  it "draws the home tile hover in the brand orange with text that counts as large" do
    tile = styles.join("static_pages.scss").read
    expect(tile).to match(/&:active\s*\{[^}]*background:\s*\$primary;/m)
    expect(tile).to match(/font-weight: lighter;\s*font-size: 1\.75rem;/)
    expect(tile).to match(/max-width: 575\.98px\) \{\s*font-size: 1\.25rem;\s*font-weight: 700;/)
    expect(ratio("#ffffff", variables.fetch("primary"))).to be >= 3.0
  end

  it "makes white text on the orange fill bold and at least 14pt" do
    rules = styles.join("accessibility.scss").read
    size = rules[/^\$large-text-size:\s*([\d.]+)rem;/, 1].to_f * 16
    expect(size).to be >= 18.66
    expect(rules).to match(/max-width: 1199\.98px\) \{\s*:root:not\(\[data-bs-theme="dark"\]\) \.navbar:not\(\.navbar-staff\) \{\s*\.nav-link,\s*\.btn\.btn-link \{\s*font-weight: 700;\s*font-size: \$large-text-size;/)
    expect(rules).to match(/\.btn\.btn-primary,\s*\.btn\.btn-outline-primary \{\s*--bs-btn-font-weight: 700;\s*--bs-btn-font-size: #\{\$large-text-size\};/)
    expect(rules).to match(/\.btn\.btn-outline-primary \{\s*--bs-btn-color: var\(--primary-text\);/)
    expect(rules).to match(/\.badge:is\(\.bg-primary, \.text-bg-primary, \.cert-badge\) \{\s*font-weight: 700;\s*font-size: \$large-text-size;/)
  end
end

RSpec.describe "Dark theme overrides" do
  let(:application) { Rails.root.join("app/javascript/entrypoints/application.scss").read }
  let(:dark_block) { application[/\[data-bs-theme="dark"\] \{\n  --primary-text:.*?\n\}\n/m] }

  def rule(selector)
    dark_block[/^  #{Regexp.escape(selector)} \{\n(.*?)^  \}/m, 1] || raise("no #{selector} rule in the dark block")
  end

  it "sets the root text variables to the light shades" do
    expect(dark_block).to match(/^  --primary-text: #\{\$primary-text-dark\};/)
    expect(dark_block).to match(/^  --secondary-text: #\{\$secondary-text-dark\};/)
    expect(dark_block).to match(/^  --bs-primary-text-emphasis: #\{\$primary-text-dark\};/)
  end

  it "uses the light shades for each outline button" do
    expect(rule(".btn-outline-primary")).to match(/--bs-btn-color: #\{\$primary-text-dark\};.*--bs-btn-border-color: #\{\$primary-text-dark\};/m)
    expect(rule(".btn-outline-secondary")).to match(/--bs-btn-color: #\{\$secondary-text-dark\};.*--bs-btn-border-color: #\{\$secondary-text-dark\};/m)
  end

  it "sets both link-primary states and keeps disabled dropdown items disabled" do
    expect(rule(".link-primary")).to match(/color: var\(--primary-text\) !important;.*&:hover,.*color: #\{tint-color/m)
    expect(rule(".dropdown-item")).to match(/&:disabled \{\n\s+color: var\(--bs-dropdown-link-disabled-color\)/)
  end
end
