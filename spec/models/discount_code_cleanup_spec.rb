# frozen_string_literal: true

require "rails_helper"

# The discount code feature is removed but its table (FK to users, price_rules,
# and referenced by cc_moneys) is kept, so destroying a user must still work.
RSpec.describe "legacy discount_codes cleanup" do
  it "destroys a user with a legacy discount code and keeps the cc_money pointing at it" do
    user = create(:user, :regular_user)
    other = create(:user, :regular_user)
    code_id = ActiveRecord::Base.connection.insert(
      "INSERT INTO discount_codes (code, user_id, created_at, updated_at) " \
      "VALUES ('OLD', #{user.id}, now(), now())"
    )
    cc = create(:cc_money, user: other)
    cc.update_column(:discount_code_id, code_id)

    expect { user.destroy! }.not_to raise_error
    expect(ActiveRecord::Base.connection.select_value("SELECT count(*) FROM discount_codes").to_i).to eq(0)
    expect(cc.reload.discount_code_id).to be_nil
  end
end
