# frozen_string_literal: true

require "rails_helper"

# Rails ships its default messages, form button texts, and date formats in English only.
# config/locales/defaults-fr.yml carries the French counterparts, so French pages that render
# model errors never show missing-translation text.
RSpec.describe "French Rails defaults" do
  # Messages are worded when read, so they are read under the French locale too.
  def french_errors(record)
    I18n.with_locale(:fr) do
      record.valid?
      record.errors.to_hash
    end
  end

  def french_full_messages(record)
    I18n.with_locale(:fr) do
      record.valid?
      record.errors.full_messages
    end
  end

  # Every leaf key of a namespace in English (project and Rails files merged).
  def leaf_keys(prefix, tree = I18n.t(prefix, locale: :en))
    return [prefix] unless tree.is_a?(Hash)

    tree.flat_map do |key, value|
      path = "#{prefix}.#{key}"
      value.is_a?(Hash) ? leaf_keys(path, value) : [path]
    end
  end

  it "has a French text for every message, form, date, time and support default English has" do
    namespaces = %w[errors.messages activerecord.errors.messages helpers date.formats date.day_names time.formats.default
                    time.am support.array datetime.relative]
    missing = namespaces.flat_map { |ns| leaf_keys(ns) }.reject { |key| I18n.exists?(key, :fr) }

    expect(missing).to be_empty, "missing in French:\n#{missing.join("\n")}"
  end

  it "words a user sign-up with blank fields in French" do
    user = User.new
    messages = french_full_messages(user)

    expect(messages).to include(a_string_matching(/Ce champ est requis|doit être rempli/))
    expect(messages.join).not_to match(/translation missing|can't be blank/i)
  end

  it "words a too-short value with the count in French" do
    expect(I18n.t("errors.messages.too_short", count: 4, locale: :fr)).to eq("est trop court (au moins 4 caractères)")
    expect(I18n.t("errors.messages.too_short", count: 1, locale: :fr)).to eq("est trop court (au moins un caractère)")
    expect(I18n.t("errors.messages.wrong_length", count: 3, locale: :fr)).to eq("ne fait pas la bonne longueur (doit comporter 3 caractères)")
  end

  it "words an invalid number and a length limit on a model in French" do
    model = Class.new do
      include ActiveModel::Validations
      attr_accessor :quantity, :code

      def self.name = "Widget"
      validates :quantity, numericality: { only_integer: true, greater_than: 2 }
      validates :code, length: { minimum: 4 }, exclusion: { in: %w[ab] }
    end.new
    model.quantity = "x"
    model.code = "ab"

    errors = french_errors(model)

    expect(errors[:quantity]).to eq(["n'est pas un nombre"])
    expect(errors[:code]).to contain_exactly("est trop court (au moins 4 caractères)", "n'est pas disponible")
  end

  it "words a taken username and email in French" do
    existing = create(:user)
    duplicate = build(:user, username: existing.username, email: existing.email)

    errors = french_errors(duplicate)

    expect(errors[:username]).to include("Ce nom d'utilisateur est déjà utilisé.")
    expect(errors[:email]).to include("Cette adresse courriel est déjà utilisée.")
    expect(errors.values.flatten.join).not_to match(/translation missing|already/i)
  end

  it "words a taken value with no project-specific text in French" do
    first = create(:booking_status, name: "Waitlisted")
    errors = french_errors(build(:booking_status, name: first.name))

    expect(errors[:name]).to eq(["n'est pas disponible"])
  end

  it "words a refused deletion in French" do
    space = create(:space)
    create(:volunteer_task, space: space)

    expect(I18n.with_locale(:fr) { space.deletion_refusals }).to eq(
      ["Impossible de supprimer l'enregistrement car il reste des tâches de bénévolat"]
    )
    expect(I18n.t("activerecord.errors.messages.restrict_dependent_destroy.has_one", record: "casier", locale: :fr))
      .to eq("Impossible de supprimer l'enregistrement car un(e) casier dépendant(e) existe")
  end

  it "keeps the English texts the project and Rails define" do
    expect(I18n.t("errors.messages.too_short", count: 4, locale: :en)).to eq("is too short (minimum is 4 characters)")
    expect(I18n.t("activerecord.errors.messages.blank", locale: :en)).to eq("This field is required.")
  end

  it "renders French form button, date and list defaults" do
    I18n.with_locale(:fr) do
      expect(I18n.t("helpers.submit.create", model: "Casier")).to eq("Créer Casier")
      expect(I18n.l(Date.new(2026, 11, 7))).to eq("07/11/2026")
      expect(%w[a b c].to_sentence).to eq("a, b et c")
    end
  end
end
