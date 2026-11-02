# frozen_string_literal: true

require "rails_helper"

# Contract: doc/api/v1/printers.md
RSpec.describe "/api/v1 printer types, assignments and issues", type: :request do
  let(:json_headers) { { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" } }
  let(:admin) { create(:user, :admin) }
  let(:staff) { create(:user, :staff) }
  let(:regular) { create(:user) }

  def body = response.parsed_body
  def error = body["error"]
  def auth(user) = { "Authorization" => "Bearer #{ApiAccessToken.issue(user).first}" }
  def api_get(path, as: nil) = get(path, headers: json_headers.merge(as ? auth(as) : {}))
  def api_send(verb, path, payload, as: nil) = public_send(verb, path, params: payload.to_json, headers: json_headers.merge(as ? auth(as) : {}))

  shared_examples "staff only" do |verb, path|
    it "401s a guest and 403s a regular user" do
      send_it = ->(user) { verb == :get ? api_get(path, as: user) : api_send(verb, path, { user_id: 1, active: false }, as: user) }
      send_it.call(nil)
      expect(response).to have_http_status(:unauthorized)
      expect(error["code"]).to eq("unauthenticated")
      send_it.call(regular)
      expect(response).to have_http_status(:forbidden)
      expect(error["code"]).to eq("forbidden")
    end
  end

  describe "GET /api/v1/printer_types" do
    let!(:um2p) { create(:printer, :UM2P_01) }
    let!(:um2p_10) { create(:printer, :UM2P_01, number: "10") }
    let!(:dremel) { create(:printer, :dremel_10_17) }

    include_examples "staff only", :get, "/api/v1/printer_types?include=printers"

    it "lists types with printers and has_issues, for staff and admin, with exact keys" do
      create(:printer_issue, printer: um2p)
      [staff, admin].each do |caller|
        api_get "/api/v1/printer_types?include=printers", as: caller
        expect(response).to have_http_status(:ok)
        expect(body.map(&:keys).uniq).to eq([%w[id name short_form available printers]])
        expect(body.flat_map { |t| t["printers"].map(&:keys) }.uniq).to eq([%w[id number maintenance has_issues]])
        type = body.find { |t| t["id"] == um2p.printer_type_id }
        expect(type).to include("name" => "Ultimaker 2+", "short_form" => "UM2P", "available" => true)
        expect(type["printers"].to_h { |p| [p["id"], p["has_issues"]] }).to eq(um2p.id => true, um2p_10.id => false)
      end
    end

    it "matches the legacy printer_data" do
      create(:printer_issue, printer: dremel, active: false)
      api_get "/api/v1/printer_types?include=printers", as: staff
      legacy = PrinterType.includes(printers: :printer_issues).map do |t|
        { "id" => t.id, "name" => t.name, "short_form" => t.short_form, "available" => t.available,
          "printers" => t.printers.map { |p| { "id" => p.id, "number" => p.number, "maintenance" => p.maintenance, "has_issues" => !p.printer_issues.empty? } } }
      end
      expect(body).to match_array(legacy)
      expect(body.find { |t| t["id"] == dremel.printer_type_id }["printers"].first["has_issues"]).to be(true)
    end

    it "omits printers without include and 422s an unknown include" do
      api_get "/api/v1/printer_types", as: staff
      expect(response).to have_http_status(:ok)
      expect(body.map(&:keys).uniq).to eq([%w[id name short_form available]])
      api_get "/api/v1/printer_types?include=users", as: staff
      expect(response).to have_http_status(:unprocessable_content)
      expect(error["fields"]).to have_key("include")
    end

    it "does not query per type or printer" do
      create_list(:printer, 3, :Random)
      count = 0
      cb = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" || payload[:sql].match?(/\A\s*(BEGIN|COMMIT|SAVEPOINT|RELEASE)/i) }
      token = auth(staff)
      ActiveSupport::Notifications.subscribed(cb, "sql.active_record") do
        get "/api/v1/printer_types?include=printers", headers: json_headers.merge(token)
      end
      expect(count).to be <= 6 # user/token lookup + types + printers + issues
    end
  end

  describe "POST /api/v1/printers/:id/assignments" do
    let!(:printer) { create(:printer, :UM3_01) }
    let(:target) { create(:user) }
    let(:path) { "/api/v1/printers/#{printer.id}/assignments" }

    include_examples "staff only", :post, "/api/v1/printers/1/assignments"

    it "creates an in-use session for the user and closes the previous one (staff and admin)" do
      [staff, admin].each do |caller|
        expect { api_send :post, path, { user_id: target.id }, as: caller }.to change(PrinterSession, :count).by(1)
        expect(response).to have_http_status(:no_content)
        expect(response.body).to be_empty
      end
      sessions = PrinterSession.where(printer_id: printer.id).order(:id)
      expect(sessions.map(&:in_use)).to eq([false, true])
      expect(sessions.map(&:user_id)).to eq([target.id, target.id])
    end

    it "accepts the user id as a numeric string" do
      api_send :post, path, { user_id: target.id.to_s }, as: staff
      expect(response).to have_http_status(:no_content)
      expect(PrinterSession.last).to have_attributes(printer_id: printer.id, user_id: target.id, in_use: true)
    end

    it "leaves other printers' sessions alone" do
      other = create(:printer, :UM3_01, number: "02")
      other_session = PrinterSession.create!(printer: other, user: target, in_use: true)
      api_send :post, path, { user_id: target.id }, as: staff
      expect(other_session.reload.in_use).to be(true)
    end

    it "clears: closes the latest session without creating one" do
      session = PrinterSession.create!(printer: printer, user: target, in_use: true)
      expect { api_send :post, path, { user_id: "clear" }, as: staff }.not_to change(PrinterSession, :count)
      expect(response).to have_http_status(:no_content)
      expect(session.reload.in_use).to be(false)
    end

    it "clearing a printer that was never used is a no-op 204 (legacy: 500)" do
      expect { api_send :post, path, { user_id: "clear" }, as: staff }.not_to change(PrinterSession, :count)
      expect(response).to have_http_status(:no_content)
    end

    it "404s an unknown printer or user and writes nothing" do
      expect do
        api_send :post, "/api/v1/printers/0/assignments", { user_id: target.id }, as: staff
        expect(response).to have_http_status(:not_found)
        api_send :post, path, { user_id: 0 }, as: staff
        expect(response).to have_http_status(:not_found)
        target.update_columns(deleted: true)
        api_send :post, path, { user_id: target.id }, as: staff
        expect(response).to have_http_status(:not_found)
      end.not_to change(PrinterSession, :count)
      expect(error["code"]).to eq("not_found")
    end

    it "422s a missing or malformed user_id" do
      api_send :post, path, {}, as: staff
      expect(response).to have_http_status(:unprocessable_content)
      expect(error["code"]).to eq("parameter_missing")
      [nil, "", "abc", "12abc", [1], { "a" => 1 }, 1.5, true].each do |bad|
        api_send :post, path, { user_id: bad }, as: staff
        expect(response).to have_http_status(:unprocessable_content), "user_id=#{bad.inspect}"
      end
      expect(PrinterSession.count).to eq(0)
    end

    it "404s a non-integer printer id at the router" do
      api_send :post, "/api/v1/printers/abc/assignments", { user_id: target.id }, as: staff
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/printer_issues" do
    let!(:printer) { create(:printer, :UM3_01) }
    let(:reporter) { create(:user, name: "Rita Reporter") }

    include_examples "staff only", :get, "/api/v1/printer_issues"

    it "lists issues with exactly the allowed keys and the reporter's name only" do
      issue = create(:printer_issue, printer: printer, reporter: reporter, summary: "Nozzle clogged", description: "bad")
      create(:printer_issue, printer: printer, active: false)
      [staff, admin].each do |caller|
        api_get "/api/v1/printer_issues", as: caller
        expect(response).to have_http_status(:ok)
        expect(body.size).to eq(2)
        expect(body.map(&:keys).uniq).to eq([%w[id printer_id reporter summary description created_at active]])
        row = body.find { |r| r["id"] == issue.id }
        expect(row).to include("printer_id" => printer.id, "reporter" => "Rita Reporter", "summary" => "Nozzle clogged",
                               "description" => "bad", "active" => true)
        expect(row["created_at"]).to eq(issue.created_at.as_json)
      end
      expect(response.body).not_to include(reporter.email)
    end

    it "matches the legacy issues list and avoids a per-issue query" do
      create_list(:printer_issue, 3, printer: printer)
      api_get "/api/v1/printer_issues", as: staff
      legacy = PrinterIssue.order(:printer_id).map do |i|
        { "id" => i.id, "printer_id" => i.printer_id, "reporter" => i.reporter&.name, "summary" => i.summary,
          "description" => i.description, "created_at" => i.created_at.as_json, "active" => i.active }
      end
      expect(body).to match_array(legacy)
      count = 0
      cb = ->(*, payload) { count += 1 if payload[:sql].match?(/FROM "users"/) }
      token = auth(staff)
      ActiveSupport::Notifications.subscribed(cb, "sql.active_record") { get "/api/v1/printer_issues", headers: json_headers.merge(token) }
      expect(count).to be <= 2 # the token's user + one reporters query
    end
  end

  describe "PATCH /api/v1/printer_issues/:id" do
    let!(:printer) { create(:printer, :UM3_01, maintenance: true) }
    let!(:issue) { create(:printer_issue, printer: printer, summary: "Bed issue", description: "x") }
    let!(:other) { create(:printer_issue, printer: printer) }
    let(:path) { "/api/v1/printer_issues/#{issue.id}" }

    include_examples "staff only", :patch, "/api/v1/printer_issues/1"

    it "resolves for staff and admin: only active changes, no email, printer untouched" do
      Setting.maintenance_email = "maint@example.com" if Setting.respond_to?(:maintenance_email=)
      [staff, admin].each do |caller|
        issue.update_columns(active: true)
        perform_enqueued_jobs do
          api_send :patch, path, { active: false }, as: caller
        end
        expect(response).to have_http_status(:no_content)
        expect(response.body).to be_empty
        expect(issue.reload).to have_attributes(active: false, summary: "Bed issue", description: "x")
      end
      expect(other.reload.active).to be(true)
      expect(printer.reload.maintenance).to be(true)
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "is idempotent on an already resolved issue" do
      issue.update_columns(active: false)
      api_send :patch, path, { active: false }, as: staff
      expect(response).to have_http_status(:no_content)
      expect(issue.reload.active).to be(false)
    end

    it "ignores other fields in the body" do
      api_send :patch, path, { active: false, summary: "hacked", printer_id: 0 }, as: staff
      expect(issue.reload).to have_attributes(summary: "Bed issue", printer_id: printer.id)
    end

    it "404s an unknown issue and a non-integer id" do
      api_send :patch, "/api/v1/printer_issues/0", { active: false }, as: staff
      expect(response).to have_http_status(:not_found)
      api_send :patch, "/api/v1/printer_issues/abc", { active: false }, as: staff
      expect(response).to have_http_status(:not_found)
    end

    it "422s anything but active:false, changing nothing" do
      api_send :patch, path, {}, as: staff
      expect(response).to have_http_status(:unprocessable_content)
      expect(error["fields"]).to eq("active" => ["is required"])
      [true, nil, "yes", 0, [false]].each do |bad|
        api_send :patch, path, { active: bad }, as: staff
        expect(response).to have_http_status(:unprocessable_content), "active=#{bad.inspect}"
      end
      expect(issue.reload.active).to be(true)
    end
  end
end
