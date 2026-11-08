# frozen_string_literal: true

require "rails_helper"

# Ordering of the admin user list and search by the "Signed in" column.
# A user shows once however many visits they have; users without any visit
# sort as if they had never signed in.
RSpec.describe "Admin::Users sorting by last sign in", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:space) { create(:space) }

  let!(:never) { create(:user, :regular_user, username: "sortnever", name: "Sort Never") }
  let!(:once) { create(:user, :regular_user, username: "sortonce", name: "Sort Once") }
  let!(:many) { create(:user, :regular_user, username: "sortmany", name: "Sort Many") }

  before do
    block_external_http!
    post login_authentication_path, params: { username_email: admin.username, password: "asa32A353#" }
    create(:lab_session, user: once, space: space, sign_in_time: 3.days.ago, sign_out_time: 3.days.ago + 1.hour)
    create(:lab_session, user: many, space: space, sign_in_time: 10.days.ago, sign_out_time: 10.days.ago + 1.hour)
    create(:lab_session, user: many, space: space, sign_in_time: 1.day.ago, sign_out_time: 1.day.ago + 1.hour)
    create(:lab_session, user: many, space: space, sign_in_time: 5.days.ago, sign_out_time: 5.days.ago + 1.hour)
  end

  def listed_usernames
    %w[sortnever sortonce sortmany].sort_by { |u| response.body.index(">#{u}<") || Float::INFINITY }
      .select { |u| response.body.include?(">#{u}<") }
  end

  def listed_count(username)
    response.body.scan(">#{username}<").size
  end

  describe "GET /admin/users" do
    it "lists each user once without a sort" do
      get admin_users_path
      expect(response).to have_http_status(:ok)
      expect(listed_usernames).to match_array(%w[sortnever sortonce sortmany])
      expect(%w[sortnever sortonce sortmany].map { |u| listed_count(u) }).to eq([1, 1, 1])
    end

    it "orders by newest sign in, newest first, with never-signed-in users last" do
      get admin_users_path(sort: "lab_sessions.sign_in_time", direction: "desc")
      expect(response).to have_http_status(:ok)
      expect(listed_usernames).to eq(%w[sortmany sortonce sortnever])
      expect(%w[sortnever sortonce sortmany].map { |u| listed_count(u) }).to eq([1, 1, 1])
    end

    it "orders by newest sign in, oldest first, with never-signed-in users first" do
      get admin_users_path(sort: "lab_sessions.sign_in_time", direction: "asc")
      expect(response).to have_http_status(:ok)
      expect(listed_usernames).to eq(%w[sortnever sortonce sortmany])
      expect(%w[sortnever sortonce sortmany].map { |u| listed_count(u) }).to eq([1, 1, 1])
    end

    it "still sorts by name" do
      get admin_users_path(sort: "name", direction: "asc")
      expect(listed_usernames).to eq(%w[sortmany sortnever sortonce])
    end
  end

  describe "GET /admin/users/search" do
    it "finds each match once without a sort" do
      get search_admin_users_path(q: "sort")
      expect(response).to have_http_status(:ok)
      expect(%w[sortnever sortonce sortmany].map { |u| listed_count(u) }).to eq([1, 1, 1])
    end

    it "orders matches by newest sign in" do
      get search_admin_users_path(q: "sort", sort: "lab_sessions.sign_in_time", direction: "desc")
      expect(response).to have_http_status(:ok)
      expect(listed_usernames).to eq(%w[sortmany sortonce sortnever])
      expect(%w[sortnever sortonce sortmany].map { |u| listed_count(u) }).to eq([1, 1, 1])
    end

    it "orders matches by oldest sign in first" do
      get search_admin_users_path(q: "sort", sort: "lab_sessions.sign_in_time", direction: "asc")
      expect(listed_usernames).to eq(%w[sortnever sortonce sortmany])
    end
  end

  # More users than fit on one page that all tie on the sort value: every user must appear on
  # exactly one page and repeated requests must return the same order.
  describe "paging through users that tie on the sort value" do
    let(:tied_time) { Time.zone.local(2026, 1, 15, 12, 0, 0) }
    let(:tied_names) { Array.new(25) { |i| format("tiepage%02d", i) } }

    before do
      travel_to(tied_time) do
        tied_names.each { |n| create(:user, :regular_user, username: n, name: "Tie Page") }
      end
      travel_back
    end

    def page_usernames(path_helper, page, **params)
      get public_send(path_helper, **params, page: page)
      expect(response).to have_http_status(:ok)
      response.body.scan(/>(tiepage\d\d)</).flatten
    end

    def expect_stable_paging(path_helper, **params)
      first = [1, 2].map { |pg| page_usernames(path_helper, pg, **params) }
      second = [1, 2].map { |pg| page_usernames(path_helper, pg, **params) }
      expect(first.flatten).to match_array(tied_names)
      expect(first.flatten.uniq.size).to eq(tied_names.size)
      expect(second).to eq(first)
    end

    {
      "the default order" => {},
      "created_at" => { sort: "created_at", direction: "asc" },
      "name" => { sort: "name", direction: "desc" },
      "newest sign in" => { sort: "lab_sessions.sign_in_time", direction: "desc" }
    }.each do |label, params|
      it "lists every user once across pages ordered by #{label}" do
        expect_stable_paging(:admin_users_path, **params)
      end

      it "finds every match once across pages ordered by #{label}" do
        expect_stable_paging(:search_admin_users_path, **params.merge(q: "tiepage"))
      end
    end

    it "lists every signed-in user once across pages" do
      users = User.where(username: tied_names)
      users.each do |u|
        create(:lab_session, user: u, space: space, sign_in_time: tied_time, sign_out_time: 1.day.from_now)
      end
      expect_stable_paging(:admin_users_path, p: "signed_in_users")
      expect_stable_paging(:admin_users_path, p: "signed_in_users", sort: "name", direction: "asc")
    end
  end
end
