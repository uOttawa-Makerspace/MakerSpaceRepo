# frozen_string_literal: true

require "rails_helper"

# Shift is retired but shifts_users rows must not be orphaned when a user,
# shift or space is destroyed.
RSpec.describe "legacy shifts_users cleanup" do
  def join_count(where)
    ActiveRecord::Base.connection.select_value("SELECT count(*) FROM shifts_users WHERE #{where}").to_i
  end

  def link(shift, user)
    ActiveRecord::Base.connection.execute("INSERT INTO shifts_users (shift_id, user_id) VALUES (#{shift.id}, #{user.id})")
  end

  it "removes join rows when a user is destroyed" do
    user = create(:user, :regular_user)
    shift = Shift.create!(start_datetime: 1.day.ago, end_datetime: 1.day.ago + 1.hour)
    link(shift, user)
    expect { user.destroy! }.to change { join_count("user_id = #{user.id}") }.from(1).to(0)
  end

  it "removes join rows when a space with shifts is destroyed" do
    space = create(:space)
    shift = Shift.create!(space_id: space.id, start_datetime: 1.day.ago, end_datetime: 1.day.ago + 1.hour)
    link(shift, create(:user, :regular_user))
    expect { space.destroy! }.to change { join_count("shift_id = #{shift.id}") }.from(1).to(0)
  end
end
