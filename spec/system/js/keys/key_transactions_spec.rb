# frozen_string_literal: true

require "rails_helper"

# Page script app/javascript/entrypoints/key_transactions.js: the deposit
# return date picker on the "Return Deposit" page. Real login, real page JS.
RSpec.describe "Key transaction deposit return", type: :system, skip_bullet: true do
  let(:admin) { create(:user, :admin) }
  let!(:space) { create(:space) }
  let!(:holder) { create(:user, :staff) }
  let!(:key) { create(:key, :regular_key_type, :held_status, space: space, user: holder, supervisor: admin) }
  let!(:transaction) { create(:key_transaction, key: key, user: holder, deposit_amount: 30) }

  before { log_in_as(admin) }

  it "prefills today in a date picker and clears it with the button" do
    visit edit_admin_key_transaction_path(transaction)
    expect(page).to have_field("deposit-return-date", with: Time.zone.today.to_s)
    expect(page).to have_css("#deposit-return-date.flatpickr-input")
    click_button "deposit-return-date-clear"
    expect(page).to have_field("deposit-return-date", with: "")
  end

  it "records the picked date as the deposit return date" do
    visit edit_admin_key_transaction_path(transaction)
    expect(page).to have_css("#deposit-return-date.flatpickr-input")
    click_button "Update Deposit"
    expect(page).to have_text("Successfully updated deposit information")
    expect(transaction.reload.deposit_return_date).to eq(Time.zone.today)
  end

  it "refuses an empty date with a message and leaves the deposit untouched" do
    visit edit_admin_key_transaction_path(transaction)
    expect(page).to have_css("#deposit-return-date.flatpickr-input")
    click_button "deposit-return-date-clear"
    click_button "Update Deposit"
    expect(page).to have_text("Something went wrong while updating the deposit")
    expect(transaction.reload.deposit_return_date).to be_nil
  end

  it "sets up the date picker when the page is reached by a link from the list" do
    transaction.update!(return_date: Time.zone.today)
    visit admin_key_transactions_path
    wait_for_app_js
    click_button "Awaiting deposit refund"
    click_link "Return Deposit"
    expect(page).to have_current_path(edit_admin_key_transaction_path(transaction))
    expect(page).to have_css("#deposit-return-date.flatpickr-input")
  end
end
