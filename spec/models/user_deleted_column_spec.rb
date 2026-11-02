# frozen_string_literal: true

require "rails_helper"

RSpec.describe "users.deleted" do
  let(:column) { User.columns_hash.fetch("deleted") }

  it "is NOT NULL and defaults to false, so every `deleted = false` query sees every row" do
    expect(column.null).to be(false)
    expect(User.new.deleted).to be(false)
  end

  it "refuses a NULL at the database" do
    user = create(:user)
    expect { user.update_column(:deleted, nil) }.to raise_error(ActiveRecord::NotNullViolation)
  end
end
