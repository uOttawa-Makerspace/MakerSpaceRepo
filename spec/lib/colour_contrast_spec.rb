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

  def variables_file = styles.join("shared/_variables.scss").read

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
    expect(compiled_css).to match(/\.platform-item \.overlay:active\{[^}]*background:\s*#e24829/)
    expect(compiled_css).to match(/font-size:\s*1\.75rem;\s*font-weight:\s*lighter/)
    expect(compiled_css).to match(/@media \(width<=575\.98px\)\{[^{]*\.overlay\{font-size:\s*1\.25rem;\s*font-weight:\s*700\}/)
    expect(ratio("#ffffff", variables.fetch("primary"))).to be >= 3.0
  end

  it "keeps the brand orange" do
    expect(variables.fetch("primary")).to eq("#e24829")
  end

  it "makes white text on the orange fill bold and at least 14pt" do
    size = variables_file[/^\$large-text-size:\s*([\d.]+)rem;/, 1].to_f * 16
    expect(size).to be >= 18.66
    navbar = ':root:not([data-bs-theme=dark]) .navbar:not(.navbar-staff) .nav-link'
    {
      navbar => { "font-weight" => "700", "font-size" => "1.167rem" },
      ".btn:is(.btn-primary,.btn-outline-primary)" => { "--bs-btn-font-weight" => "700" },
      ".btn:is(.btn-primary,.btn-outline-primary):not(.btn-lg)" => { "--bs-btn-font-size" => "1.167rem" },
      ".badge:is(.bg-primary,.text-bg-primary,.cert-badge)" => { "font-weight" => "700", "font-size" => "1.167rem" },
      ".fc .fc-button-primary" => { "font-weight" => "700", "font-size" => "1.167rem" },
      ".nav-pills .nav-link" => { "font-size" => "1.167rem" },
      ".nav-pills .nav-link.active" => { "font-weight" => "700!important" },
      ".nav-pills .show>.nav-link" => { "font-weight" => "700!important" }
    }.each do |selector, expected|
      expect(css_declarations(selector)).to include(expected), "#{selector} lacks #{expected}"
    end
  end

  it "leaves large buttons at their own size and small buttons at their own height" do
    expect(compiled_css).not_to match(/\.btn-lg:is\(\.btn-primary/)
    expect(css_declarations(".btn-lg")).to include("--bs-btn-font-size" => "1.25rem")
    expect(css_declarations(".btn-sm:is(.btn-primary,.btn-outline-primary)")).to include("--bs-btn-line-height" => "1.125")
    expect(css_declarations(".input-group-sm>.btn:is(.btn-primary,.btn-outline-primary)")).to include("font-size" => "1.167rem", "line-height" => "1.125")
  end

  it "wraps the calendar toolbar on phones so its larger buttons stay on screen" do
    expect(compiled_css).to match(/@media \(width<=575\.98px\)\{\.fc \.fc-header-toolbar\{[^}]*flex-wrap:\s*wrap/)
  end

  it "draws outline buttons in the darker text orange at rest" do
    expect(css_declarations(".btn.btn-outline-primary")).to include("--bs-btn-color" => "var(--primary-text)")
  end

  it "expands the main navbar only from 1600px, where its 14pt links fit" do
    expect(compiled_css).to match(/@media \(width>=1600px\)\{\.navbar-expand-xxxl\{/)
    header = Rails.root.join("app/views/layouts/_header.html.erb").read
    expect(header).to include("navbar-expand-xxxl")
    expect(header).not_to match(/navbar-expand-xl|d-xl-|px-xl-/)
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
