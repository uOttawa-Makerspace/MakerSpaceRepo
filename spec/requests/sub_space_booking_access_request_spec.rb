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

  def make_row(status:, created_at: Time.current, **attrs)
    UserBookingApproval.create!(
      { user: user, identity: "Other", comments: "old", date: Date.current,
        status: status, created_at: created_at }.merge(attrs)
    )
  end

  before { log_in!(user) }

  it "refuses a new request while one is pending" do
    make_row(status: "pending")
    request_access
    expect(flash[:alert]).to eq("You have already requested access.")
    expect(UserBookingApproval.where(user: user).count).to eq(1)
  end

  it "tells a user who has current access that they already have it" do
    user.update!(booking_approval: true)
    make_row(status: "approved")
    request_access
    expect(flash[:alert]).to eq("You already have booking access.")
    expect(UserBookingApproval.where(user: user).count).to eq(1)
  end

  it "allows a new request when only an old approved row remains and access was cleared" do
    old = make_row(status: "approved", created_at: 1.year.ago)
    request_access(comments: "again")
    expect(flash[:notice]).to eq("Access request submitted successfully.")
    expect(UserBookingApproval.where(user: user).count).to eq(2)
    expect(old.reload.approved).to be(true)
    expect(UserBookingApproval.unscoped.where(user: user, approved: false).pick(:comments)).to eq("again")
  end

  it "mails the recipients when a user asks again, and keeps the old row", :perform_jobs do
    make_row(status: "approved", created_at: 1.year.ago)
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
    make_row(status: "pending", created_at: 2.days.ago)
    make_row(status: "approved", created_at: 1.day.ago)
    get sub_space_booking_index_path
    expect(response.body).to include("Access Pending")
  end

  it "shows the request form when the only row is an old approved one and access was cleared" do
    make_row(status: "approved", created_at: 1.year.ago)
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
      old = make_row(status: "approved", created_at: 1.year.ago, staff: admin)
      old_attrs = old.reload.attributes
      pending = make_row(status: "pending", comments: "new")
      expect(approval_mail_recipients).to eq([user.email])
      expect(pending.reload.approved).to be(true)
      expect(pending.staff_id).to eq(admin.id)
      expect(old.reload.attributes).to eq(old_attrs)
      expect(user.reload.booking_approval).to be(true)
      expect(UserBookingApproval.where(user: user).count).to eq(2)
    end

    it "approves the newest pending request when an approved row is newer than it" do
      pending = make_row(status: "pending", created_at: 2.days.ago)
      newer = make_row(status: "approved", created_at: 1.day.ago)
      approve_user
      expect(pending.reload.approved).to be(true)
      expect(newer.reload.staff_id).to be_nil
    end

    it "approves the later-created of two pending requests made at the same moment" do
      moment = 1.day.ago.change(usec: 0)
      first = make_row(status: "pending", created_at: moment)
      second = make_row(status: "pending", created_at: moment)
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
      make_row(status: "approved")
      expect(approval_mail_recipients).to be_empty
      expect(flash[:notice]).to eq("#{user.name} already has booking access.")
      expect(UserBookingApproval.where(user: user).count).to eq(1)
    end
  end

  describe "declining and revoking" do
    let(:admin) { create(:user, :admin) }

    before do
      %i[pending approved rejected].each { |status| create(:booking_status, status) }
      log_in!(admin)
    end

    def deny(row, **params)
      put deny_access_sub_space_booking_index_path, params: { id: row.id }.merge(params)
    end

    # The emails listed in the admin table under the given heading.
    def listed_emails(heading)
      get sub_space_booking_index_path
      table = Nokogiri::HTML(response.body).at_xpath("//h5[contains(., '#{heading}')]/following::table[1]")
      table.css("tbody tr small").map(&:text)
    end

    it "declining a pending request keeps it as declined, with who, when and why" do
      row = make_row(status: "pending")
      decided_at = Time.current.change(usec: 0)
      travel_to(decided_at) { deny(row, reason: "  Not a GNG student  ") }

      expect(flash[:notice]).to eq("Access request declined successfully.")
      row.reload
      expect(row).to have_attributes(status: "declined", approved: false, decided_by_id: admin.id,
                                     decided_at: decided_at, reason: "Not a GNG student")
      expect(user.reload.booking_access_pending?).to be(false)
      expect(listed_emails("Pending Requests")).not_to include(user.email)
    end

    it "declining leaves access the user already holds" do
      user.update!(booking_approval: true)
      row = make_row(status: "pending")
      deny(row)
      expect(row.reload.status).to eq("declined")
      expect(row.reason).to be_nil
      expect(user.reload.booking_approval).to be(true)
    end

    it "revoking marks every approved request of the user revoked, and the approved list no longer shows the user" do
      user.update!(booking_approval: true)
      older = make_row(status: "approved", staff: admin, created_at: 1.year.ago)
      row = make_row(status: "approved", staff: admin)
      other = create(:user, :regular_user, booking_approval: true)
      kept = make_row(status: "approved", staff: admin, user: other)

      deny(row, reason: "Misused the room")

      expect(flash[:notice]).to eq("Booking access revoked successfully.")
      [row, older].each do |revoked|
        expect(revoked.reload).to have_attributes(status: "revoked", approved: false, decided_by_id: admin.id,
                                                  reason: "Misused the room", staff_id: admin.id)
      end
      expect(user.reload.booking_approval).to be(false)
      expect(kept.reload.status).to eq("approved")
      expect(listed_emails("Approved Users")).to eq([other.email])
    end

    it "revokes an approved request saved without an identity, keeping the identity empty" do
      user.update!(booking_approval: true)
      row = make_row(status: "approved", staff: admin)
      row.update_column(:identity, nil)
      deny(row)
      expect(row.reload).to have_attributes(status: "revoked", identity: nil)
      expect(user.reload.booking_approval).to be(false)
    end

    it "revokes even when the user record is otherwise invalid" do
      user.update!(booking_approval: true)
      user.update_column(:gender, "Unlisted")
      row = make_row(status: "approved", staff: admin)
      deny(row)
      expect(row.reload.status).to eq("revoked")
      expect(user.reload.booking_approval).to be(false)
    end

    it "refuses to answer a declined request again and changes nothing" do
      row = make_row(status: "pending")
      deny(row, reason: "first")
      before = row.reload.attributes

      deny(row, reason: "second")
      expect(flash[:alert]).to eq("Failed to decline or revoke: This request was already declined.")
      expect(row.reload.attributes).to eq(before)
    end

    it "refuses to approve a declined request" do
      row = make_row(status: "pending")
      deny(row)
      perform_enqueued_jobs { put approve_access_sub_space_booking_index_path, params: { id: row.id } }

      expect(flash[:alert]).to eq("Failed to approve: This request was already declined.")
      expect(row.reload.status).to eq("declined")
      expect(user.reload.booking_approval).to be(false)
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "lets a user whose request was declined ask again, as a new pending request" do
      row = make_row(status: "pending")
      deny(row)
      log_in!(user)
      request_access
      expect(flash[:notice]).to eq("Access request submitted successfully.")
      expect(UserBookingApproval.where(user: user).pluck(:status)).to contain_exactly("declined", "pending")
    end
  end
end
