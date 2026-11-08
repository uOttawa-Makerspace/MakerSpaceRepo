# frozen_string_literal: true

require "rails_helper"

# Full validation messages read "<attribute> <message>". The French attribute names live in
# config/locales/attributes-fr.yml; English pages show Rails' humanized attribute name.
RSpec.describe "French attribute names" do
  def full_messages(record, locale)
    I18n.with_locale(locale) do
      record.valid?
      record.errors.full_messages
    end
  end

  it "names the username in a French sign-up message" do
    existing = create(:user)
    duplicate = build(:user, username: existing.username)

    expect(full_messages(duplicate, :fr)).to include("Nom d'utilisateur Ce nom d'utilisateur est déjà utilisé.")
  end

  it "keeps the English sign-up message unchanged" do
    existing = create(:user)
    duplicate = build(:user, username: existing.username)

    expect(full_messages(duplicate, :en)).to include("Username This username is already in use.")
  end

  it "names blank fields of several models in French and in English" do
    expect(full_messages(TimePeriod.new, :fr)).to include(
      "Nom Ce champ est requis.", "Date de début Ce champ est requis.", "Date de fin Ce champ est requis."
    )
    expect(full_messages(TimePeriod.new, :en)).to include(
      "Name This field is required.", "Start date This field is required.", "End date This field is required."
    )
    expect(full_messages(Event.new, :fr)).to include("Heure de début Ce champ est requis.")
    expect(full_messages(Event.new, :en)).to include("Start time This field is required.")
  end

  it "has a French name for every validated attribute of the models that show errors" do
    models = %w[User LockerRental Locker LockerSize VolunteerHour JobService JobServiceGroup JobOption JobType TimePeriod
                Key KeyRequest SubSpaceBooking Event CouponCode OrderItem Help ChatMessage QuickAccessLink
                MembershipTier Space SubSpace]
    missing = models.flat_map do |name|
      klass = name.constantize
      # User#email and User#student_id are named in fr.yml.
      klass.validators.flat_map(&:attributes).uniq.excluding(*(name == "User" ? %i[email student_id] : [])).reject do |attribute|
        I18n.exists?("activerecord.attributes.#{klass.model_name.i18n_key}.#{attribute}", :fr)
      end.map { |attribute| "#{name}.#{attribute}" }
    end

    expect(missing).to be_empty, "no French attribute name for:\n#{missing.join("\n")}"
  end
end
