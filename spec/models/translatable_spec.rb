# frozen_string_literal: true

require "rails_helper"

RSpec.describe Translatable do
  let(:klass) do
    Class.new do
      include Translatable

      translates :title, :body
      translates :label, prefix: "localized_"
      translates :name, prefix: "t_", bare_en: true

      def initialize(attributes)
        @attributes = attributes
      end

      def [](attribute)
        @attributes.fetch(attribute.to_sym)
      end
    end
  end

  def record(**attributes)
    klass.new({ title_en: nil, title_fr: nil, body_en: nil, body_fr: nil, label_en: nil, label_fr: nil, name: nil, name_fr: nil }.merge(attributes))
  end

  describe "reading" do
    let(:full) { record(title_en: "Hello", title_fr: "Bonjour") }

    it "reads <attribute>_<locale> for the current locale" do
      I18n.with_locale(:en) { expect(full.title).to eq("Hello") }
      I18n.with_locale(:fr) { expect(full.title).to eq("Bonjour") }
    end

    it "takes an explicit locale, symbol or string" do
      expect(full.title(:fr)).to eq("Bonjour")
      expect(full.title("fr")).to eq("Bonjour")
      expect(full.title(:en)).to eq("Hello")
    end

    it "reads a locale the site does not translate into as the default locale" do
      expect(full.title(:de)).to eq("Hello")
    end

    it "defines one reader per attribute, named with the prefix" do
      expect(klass.new({})).to respond_to(:title, :body, :localized_label, :t_name)
      expect(klass.new({})).not_to respond_to(:label)
    end
  end

  describe "falling back to the other language" do
    [nil, "", "   "].each do |blank|
      it "uses the other language when the current one is #{blank.inspect}" do
        expect(record(title_en: blank, title_fr: "Bonjour").title(:en)).to eq("Bonjour")
        expect(record(title_en: "Hello", title_fr: blank).title(:fr)).to eq("Hello")
      end
    end

    it "does not fall back when the current language has text" do
      expect(record(title_en: "Hello", title_fr: "Bonjour").title(:fr)).to eq("Bonjour")
    end

    it "gives back the stored blank when every language is blank" do
      expect(record(title_en: "", title_fr: nil).title(:en)).to eq("")
      expect(record(title_en: nil, title_fr: nil).title(:fr)).to be_nil
    end

    it "falls back per attribute" do
      item = record(title_en: "Hello", title_fr: "", body_en: "", body_fr: "Corps")
      expect([item.title(:fr), item.body(:en)]).to eq(%w[Hello Corps])
    end
  end

  describe "bare_en: true" do
    it "reads English from the bare column and French from the _fr column" do
      item = record(name: "Draft", name_fr: "Brouillon")
      expect(item.t_name(:en)).to eq("Draft")
      expect(item.t_name(:fr)).to eq("Brouillon")
    end

    it "falls back both ways" do
      expect(record(name: "Draft", name_fr: "").t_name(:fr)).to eq("Draft")
      expect(record(name: " ", name_fr: "Brouillon").t_name(:en)).to eq("Brouillon")
    end
  end

  describe "prefix:" do
    it "names the reader with the prefix but reads the plain columns" do
      expect(record(label_en: "L", label_fr: "E").localized_label(:fr)).to eq("E")
    end
  end
end
