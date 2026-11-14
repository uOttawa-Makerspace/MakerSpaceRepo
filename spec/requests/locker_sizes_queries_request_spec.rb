# frozen_string_literal: true

require "rails_helper"

# The locker request page lists every locker size with the number of its lockers the viewer's audience may still
# rent: lockers of that audience without an active rental (a member sees the general ones, staff the staff ones). The
# counts are read in one grouped query, so the number of queries does not grow with the number of sizes.
RSpec.describe "Locker request page: size counts", type: :request do
  let(:member) { create(:user, :regular_user) }

  def log_in!(user)
    post login_authentication_path, params: { username_email: user.username, password: "asa32A353#" }
    expect(response).to redirect_to(root_path)
  end

  before do
    LockerOption.where(name: [LockerOption::LOCKER_PRODUCT_LINK, LockerOption::LOCKERS_ENABLED]).delete_all
    LockerOption.lockers_enabled = true
  end

  # A size with +free+ general lockers, one rented general locker and one staff locker.
  def size!(name, free:)
    create(:locker_size, size: name).tap do |size|
      create_list(:locker, free, locker_size: size, audience: "general")
      rented = create(:locker, locker_size: size, audience: "general")
      create(:locker_rental, :active, locker: rented, rented_by: create(:user, :regular_user))
      create(:locker, locker_size: size, audience: "staff")
    end
  end

  def size_rows
    Nokogiri::HTML(response.body).css("table.table-hover tbody tr").map { |row| row.css("td").first(2).map { |td| td.text.squish } }
  end

  def queries_for(path)
    get path
    count_queries { get path }
  end

  it "shows each size, in id order, with the lockers its audience may still rent" do
    size!("Small", free: 2)
    size!("Large", free: 0)
    create(:locker_size, size: "Empty")
    log_in!(member)

    get new_locker_rental_path

    expect(response).to have_http_status(:ok)
    expect(size_rows).to eq([%w[2 Small], %w[0 Large], %w[0 Empty]])
  end

  it "counts the staff lockers for staff" do
    size!("Small", free: 2)
    log_in!(create(:user, :staff))

    get new_locker_rental_path

    expect(size_rows).to eq([%w[1 Small]])
  end

  it "runs the same number of queries for two sizes as for five" do
    log_in!(member)
    2.times { |i| size!("Size #{i}", free: i) }
    two = queries_for(new_locker_rental_path)
    3.times { |i| size!("More #{i}", free: i) }
    five = queries_for(new_locker_rental_path)

    expect(size_rows.size).to eq(5)
    expect(five).to eq(two)
  end
end
