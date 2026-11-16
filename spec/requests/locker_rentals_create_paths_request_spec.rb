# frozen_string_literal: true

require "rails_helper"

# Pins every path of POST /locker_rentals as it behaves now: staff and member, free (assigned active) and paid
# (sent to checkout), a request that already waits, a locker that is taken, an unknown renter and a failed
# validation. Each example checks the stored rental, the mail delivered, the flash and where the response goes.
RSpec.describe "LockerRentals create paths", type: :request do
  include ApplicationHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:staff) { create(:user, :staff) }
  let(:member) { create(:user, :regular_user) }
  let(:tenant) { create(:user, :regular_user) }
  let(:locker) { create(:locker) }
  let(:now) { Time.zone.local(2026, 10, 5, 10, 0, 0) }

  def log_in!(user)
    post login_authentication_path, params: { username_email: user.username, password: "asa32A353#" }
    expect(response).to redirect_to(root_path)
  end

  def create_rental(fields, headers: {})
    travel_to(now) do
      perform_enqueued_jobs { post locker_rentals_path, params: { locker_rental: fields }, headers: headers }
    end
  end

  def sent
    ActionMailer::Base.deliveries.map { |m| [m.to, m.subject] }
  end

  def staff_fields(**extra)
    { requested_as: "staff", rented_by_id: tenant.id, locker_id: locker.id }.merge(extra)
  end

  before do
    LockerOption.where(name: [LockerOption::LOCKER_PRODUCT_LINK, LockerOption::LOCKERS_ENABLED]).delete_all
    LockerOption.lockers_enabled = true
    ActionMailer::Base.deliveries.clear
    allow(ShopifyAPI::Clients::Graphql::Admin).to receive(:new).and_raise("no Shopify call is expected on create")
  end

  context "as staff" do
    before { log_in!(staff) }

    it "assigns active (free): decided by staff, ends this semester, mails the renter, says assigned, goes back" do
      create_rental(staff_fields(state: "active"), headers: { "HTTP_REFERER" => "http://www.example.com/lockers" })
      rental = LockerRental.order(:id).last
      expect(rental).to have_attributes(state: "active", decided_by_id: staff.id, rented_by_id: tenant.id, locker_id: locker.id)
      expect(rental.owned_until.utc.iso8601(6)).to eq("2026-12-31T23:59:59.999999Z")
      expect(sent).to eq([[[tenant.email], "Locker #{locker.specifier} has been assigned for you"]])
      expect(flash[:notice]).to eq("Locker assigned")
      expect(response).to redirect_to("http://www.example.com/lockers")
    end

    it "sends to checkout (paid) with no date: ends this semester, checkout mail, no notice" do
      create_rental(staff_fields(state: "await_payment"))
      rental = LockerRental.order(:id).last
      expect(rental).to have_attributes(state: "await_payment", decided_by_id: staff.id)
      expect(rental.owned_until.utc.iso8601(6)).to eq("2026-12-31T23:59:59.999999Z")
      expect(sent).to eq([[[tenant.email], "Your locker rental for locker #{locker.specifier} is ready for checkout"]])
      expect(flash[:notice]).to be_nil
      expect(response).to redirect_to(new_locker_rental_path)
    end

    it "lets indefinite clear a submitted date for a rental sent to checkout too" do
      create_rental(staff_fields(state: "await_payment", owned_until: "2027-01-10", indefinite: "1"))
      expect(LockerRental.order(:id).last).to have_attributes(state: "await_payment", owned_until: nil)
    end

    it "keeps a reviewing rental undecided: no decider, the submitted date untouched, staff are mailed" do
      create_rental(staff_fields(state: "reviewing", locker_id: nil, owned_until: "2027-01-10", indefinite: "1"))
      rental = LockerRental.order(:id).last
      expect(rental).to have_attributes(state: "reviewing", decided_by_id: nil, rented_by_id: tenant.id)
      expect(rental.owned_until.to_date).to eq(Date.new(2027, 1, 10))
      expect(sent).to eq([[["ceed@uottawa.ca"], "New locker request"]])
      expect(flash[:notice]).to be_nil
    end

    it "with no renter named, rents to the staff member" do
      create_rental(staff_fields(state: "active").except(:rented_by_id))
      expect(LockerRental.order(:id).last.rented_by_id).to eq(staff.id)
    end

    it "refuses a renter's second waiting request with 422, the form and no mail" do
      create(:locker_rental, rented_by: tenant)
      expect { create_rental(staff_fields(state: "await_payment")) }.not_to change(LockerRental, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Errors:")
      expect(sent).to be_empty
    end

    it "refuses a taken locker with 422 and no mail" do
      create(:locker_rental, :active, locker: locker)
      expect { create_rental(staff_fields(state: "active")) }.not_to change(LockerRental, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("has already been taken")
      expect(sent).to be_empty
    end

    it "refuses an unknown renter username with 422 and 'User not found', creating nothing" do
      fields = staff_fields(state: "active").except(:rented_by_id).merge(rented_by_username: "nobody-here")
      expect { create_rental(fields) }.not_to change(LockerRental, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("User not found")
      expect(sent).to be_empty
    end

    it "refuses an active rental with no locker (validation failure) with 422" do
      expect { create_rental(staff_fields(state: "active", locker_id: nil)) }.not_to change(LockerRental, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Errors:")
      expect(sent).to be_empty
    end

    it "creates even when lockers are switched off" do
      LockerOption.lockers_enabled = false
      expect { create_rental(staff_fields(state: "active")) }.to change(LockerRental, :count).by(1)
    end
  end

  context "as a member" do
    before { log_in!(member) }

    it "files a reviewing request for themself, ignoring staff fields, and mails staff" do
      create_rental({ requested_as: "general", state: "active", locker_id: locker.id, rented_by_id: tenant.id,
                      owned_until: "2027-01-10", indefinite: "1" })
      rental = LockerRental.order(:id).last
      expect(rental).to have_attributes(state: "reviewing", rented_by_id: member.id, locker_id: nil, owned_until: nil,
                                        decided_by_id: nil)
      expect(sent).to eq([[["ceed@uottawa.ca"], "New locker request"]])
      expect(flash[:notice]).to be_nil
      expect(response).to redirect_to(new_locker_rental_path)
    end

    it "ignores an unknown renter username (only staff name renters)" do
      expect { create_rental({ requested_as: "general", rented_by_username: "nobody-here" }) }
        .to change(LockerRental, :count).by(1)
      expect(LockerRental.order(:id).last.rented_by_id).to eq(member.id)
    end

    it "refuses a second waiting request with 422 and no mail" do
      create(:locker_rental, rented_by: member)
      expect { create_rental({ requested_as: "general" }) }.not_to change(LockerRental, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(sent).to be_empty
    end

    it "is turned away with the not-accepted alert when lockers are switched off" do
      LockerOption.lockers_enabled = false
      expect { create_rental({ requested_as: "general" }) }.not_to change(LockerRental, :count)
      expect(response).to redirect_to(locker_rentals_path)
      expect(flash[:alert]).to eq(I18n.t("errors.lockers.not_accepted"))
      expect(sent).to be_empty
    end
  end
end
