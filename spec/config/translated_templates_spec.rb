# frozen_string_literal: true

require "rails_helper"

# Every template, mails included, takes its wording from config/locales. A literal English
# sentence, label or attribute in a template fails here; add a locale key (English and French)
# instead. Templates that still have literal text are listed in untranslated_templates.txt, and
# that list only shrinks: a listed template that has become clean must be taken off it.
RSpec.describe "Translated templates" do
  baseline_file = Rails.root.join("spec/config/untranslated_templates.txt")
  baseline = baseline_file.readlines(chomp: true).grep_v(/\A\s*(#|\z)/)

  # .js.erb responses are JavaScript, not markup; a template with a locale in its name
  # (_waiver.fr.erb) is itself the translation.
  templates = Rails.root.glob("app/{views,components}/**/*.erb").map { |path| path.relative_path_from(Rails.root).to_s }
                   .reject { |path| path.end_with?(".js.erb") || path.match?(/\.(en|fr)\./) }.sort

  def literals(path)
    source = Rails.root.join(path).read
    LiteralTextScan.visible_literals(source) + LiteralTextScan.literal_attributes(source) +
      LiteralTextScan.literal_arguments(source)
  end

  (templates - baseline).each do |path|
    it "#{path} has no literal text" do
      expect(literals(path)).to eq([])
    end
  end

  (templates & baseline).each do |path|
    it "#{path} still has literal text (take it off #{baseline_file.basename} once it is clean)" do
      expect(literals(path)).not_to be_empty
    end
  end

  it "lists only existing templates, once each, in order" do
    expect(baseline - templates).to eq([])
    expect(baseline).to eq(baseline.uniq.sort)
  end

  it "has a French twin for every English-only template" do
    english = Rails.root.glob("app/views/**/*.en.*").map { |path| path.to_s.sub(".en.", ".fr.") }

    expect(english.reject { |path| File.exist?(path) }).to eq([])
  end
end
