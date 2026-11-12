# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261112220000_add_locale_to_users")

RSpec.describe AddLocaleToUsers do
  let(:conn) { ActiveRecord::Base.connection }

  def migrate(direction)
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(direction) }
  end

  def column = conn.columns(:users).find { |c| c.name == "locale" }

  def constraint? = conn.check_constraints(:users).any? { |c| c.name == described_class::CONSTRAINT }

  it "adds a nullable column with no default and a constraint limiting it to en, fr or NULL" do
    expect(column).to have_attributes(null: true, default: nil)
    expect(constraint?).to be(true)

    user = create(:user)
    expect(user.reload.locale).to be_nil
    expect { conn.transaction(requires_new: true) { user.update_column(:locale, "de") } }.to raise_error(ActiveRecord::StatementInvalid, /users_locale_supported/)
    user.update_column(:locale, "fr")
    expect(user.reload.locale).to eq("fr")
  end

  it "removes the column and constraint on down, keeping every user row, and restores them on up" do
    user = create(:user)
    count = User.count

    migrate(:down)
    begin
      expect(column).to be_nil
      expect(constraint?).to be(false)
      expect(conn.select_value("SELECT COUNT(*) FROM users").to_i).to eq(count)
      expect(conn.select_value("SELECT email FROM users WHERE id = #{user.id}")).to eq(user.email)
    ensure
      migrate(:up)
    end
    User.reset_column_information
    expect(column).to be_present
    expect(constraint?).to be(true)
    expect { migrate(:up) }.not_to raise_error
  end
end
