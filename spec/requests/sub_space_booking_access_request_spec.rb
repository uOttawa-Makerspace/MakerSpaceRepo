# frozen_string_literal: true

require "rails_helper"

# Asking for booking access again when the user already has request rows.
RSpec.describe "Booking access requests", type: :request do
  let(:user) { create(:user, :regular_user, booking_approval: false) }

  def log_in!(account)
    post login_authentication_path,
         params: { username_email: account.username, password: "asa32A353#" }
    follow_redirect!
  end

  def request_access(comments: "please", identity: "Other")
    put request_access_sub_space_booking_index_path,
        params: { comments: comments, identity: identity }
  end

  def make_row(approved:, created_at: Time.current, **attrs)
    UserBookingApproval.create!(
      { user: user, identity: "Other", comments: "old", date: Date.current,
        approved: approved, created_at: created_at }.merge(attrs)
    )
  end

  before { log_in!(user) }

  it "refuses a new request while one is pending" do
    make_row(approved: false)
    request_access
    expect(flash[:alert]).to eq("You have already requested access.")
    expect(UserBookingApproval.where(user: user).count).to eq(1)
  end

  it "tells a user who has current access that they already have it" do
    user.update!(booking_approval: true)
    make_row(approved: true)
    request_access
    expect(flash[:alert]).to eq("You already have booking access.")
    expect(UserBookingApproval.where(user: user).count).to eq(1)
  end

  it "allows a new request when only an old approved row remains and access was cleared" do
    old = make_row(approved: true, created_at: 1.year.ago)
    request_access(comments: "again")
    expect(flash[:notice]).to eq("Access request submitted successfully.")
    expect(UserBookingApproval.where(user: user).count).to eq(2)
    expect(old.reload.approved).to be(true)
    expect(UserBookingApproval.unscoped.where(user: user, approved: false).pick(:comments)).to eq("again")
  end

  it "mails the recipients when a user asks again, and keeps the old row", :perform_jobs do
    make_row(approved: true, created_at: 1.year.ago)
    request_access
    expect(ActionMailer::Base.deliveries.flat_map(&:to)).to eq(["mtc@uottawa.ca"])
  end

  it "keeps one pending request when the form is submitted twice" do
    request_access
    request_access(comments: "again")
    expect(flash[:alert]).to eq("You have already requested access.")
    expect(UserBookingApproval.where(user: user, approved: false).count).to eq(1)
  end

  it "shows Access Pending when any request is pending, even behind a newer approved row" do
    make_row(approved: false, created_at: 2.days.ago)
    make_row(approved: true, created_at: 1.day.ago)
    get sub_space_booking_index_path
    expect(response.body).to include("Access Pending")
  end

  it "shows the request form when the only row is an old approved one and access was cleared" do
    make_row(approved: true, created_at: 1.year.ago)
    get sub_space_booking_index_path
    expect(response.body).to include("Request Booking Access")
    expect(response.body).not_to include("Access Pending")
  end

  describe "approving by user id" do
    let(:admin) { create(:user, :admin) }

    before do
      log_in!(admin)
    end

    def approve_user
      put approve_access_sub_space_booking_index_path, params: { user_id: user.id }
    end

    def approval_mail_recipients
      ActionMailer::Base.deliveries.clear
      perform_enqueued_jobs { approve_user }
      ActionMailer::Base.deliveries.flat_map(&:to)
    end

    it "approves the pending request and leaves an older approved row unchanged" do
      old = make_row(approved: true, created_at: 1.year.ago, staff: admin)
      old_attrs = old.reload.attributes
      pending = make_row(approved: false, comments: "new")
      expect(approval_mail_recipients).to eq([user.email])
      expect(pending.reload.approved).to be(true)
      expect(pending.staff_id).to eq(admin.id)
      expect(old.reload.attributes).to eq(old_attrs)
      expect(user.reload.booking_approval).to be(true)
      expect(UserBookingApproval.where(user: user).count).to eq(2)
    end

    it "approves the newest pending request when an approved row is newer than it" do
      pending = make_row(approved: false, created_at: 2.days.ago)
      newer = make_row(approved: true, created_at: 1.day.ago)
      approve_user
      expect(pending.reload.approved).to be(true)
      expect(newer.reload.staff_id).to be_nil
    end

    it "approves the later-created of two pending requests made at the same moment" do
      moment = 1.day.ago.change(usec: 0)
      first = make_row(approved: false, created_at: moment)
      second = make_row(approved: false, created_at: moment)
      approve_user
      expect(second.reload.approved).to be(true)
      expect(first.reload.approved).to be(false)
    end

    it "creates a new approved row when the user has no pending request" do
      expect(approval_mail_recipients).to eq([user.email])
      row = UserBookingApproval.find_by!(user: user)
      expect(row.approved).to be(true)
      expect(row.identity).to eq("Other")
      expect(user.reload.booking_approval).to be(true)
    end

    it "tells the admin when the user already has access and changes nothing" do
      user.update!(booking_approval: true)
      make_row(approved: true)
      expect(approval_mail_recipients).to be_empty
      expect(flash[:notice]).to eq("#{user.name} already has booking access.")
      expect(UserBookingApproval.where(user: user).count).to eq(1)
    end
  end
end
