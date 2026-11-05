# frozen_string_literal: true

require "rails_helper"

# Contract: doc/api/v1/contact_infos.md
RSpec.describe "GET /api/v1/contact_infos", type: :request do
  def body = response.parsed_body

  let!(:zeta) { create(:contact_info, name: "Zeta Desk", email: "z@example.com", address: "1 Zeta St", phone_number: "613-555-0100", show_hours: true) }
  let!(:alpha) { create(:contact_info, name: "Alpha Lab", email: "a@example.com", show_hours: true) }
  let!(:hidden_contact) { create(:contact_info, name: "Hidden", show_hours: false) }
  let!(:unset_contact) { create(:contact_info, name: "Unset", show_hours: nil) }

  before do
    create(:opening_hour, contact_info: alpha, target_en: "Students", target_fr: "Etudiants", notes_en: "Bring ID",
           monday_opening: "09:00", monday_closing: "17:30", sunday_closed_all_day: :closed,
           saturday_closed_all_day: :hidden)
    create(:opening_hour, contact_info: alpha, target_en: "Hidden week", target_fr: "Semaine", closed_all_week: :hidden)
    create(:opening_hour, contact_info: alpha, target_en: "Summer", target_fr: "Ete", closed_all_week: :closed)
    create(:opening_hour, contact_info: hidden_contact, target_en: "x", target_fr: "y")
  end

  after do
    OpeningHour.where(contact_info_id: [zeta, alpha, hidden_contact, unset_contact].map(&:id)).delete_all
    [zeta, alpha, hidden_contact, unset_contact].each(&:destroy)
  end

  it "is public, lists only show_hours contacts by name, with an exact key set" do
    get "/api/v1/contact_infos"
    expect(response).to have_http_status(:ok)
    expect(response.headers["Set-Cookie"]).to be_nil
    expect(body.map { |c| c["name"] }).to eq(["Alpha Lab", "Zeta Desk"])
    expect(body.map(&:keys).uniq).to eq([%w[name email address phone_number opening_hours]])
    expect(body.last).to include("email" => "z@example.com", "address" => "1 Zeta St", "phone_number" => "613-555-0100",
                                 "opening_hours" => [])
  end

  it "shapes opening hours from the real columns and drops hidden weeks" do
    get "/api/v1/contact_infos"
    hours = body.first["opening_hours"]
    expect(hours.map { |h| h["target_en"] }).to eq(%w[Students Summer])
    expect(hours.map(&:keys).uniq).to eq([%w[target_en target_fr notes_en notes_fr closed_all_week days]])
    students = hours.first
    expect(students).to include("target_fr" => "Etudiants", "notes_en" => "Bring ID", "notes_fr" => nil, "closed_all_week" => false)
    expect(students["days"].keys).to eq(%w[sunday monday tuesday wednesday thursday friday saturday])
    expect(students["days"].values.map(&:keys).uniq).to eq([%w[status opening closing]])
    expect(students["days"]["monday"]).to eq("status" => "open", "opening" => "09:00", "closing" => "17:30")
    expect(students["days"]["sunday"]).to eq("status" => "closed", "opening" => nil, "closing" => nil)
    expect(students["days"]["saturday"]["status"]).to eq("hidden")
    expect(hours.last["closed_all_week"]).to eq(true)
  end

  it "does not run a query per contact" do
    create_list(:contact_info, 3, show_hours: true).each { |c| create(:opening_hour, contact_info: c) }
    queries = []
    sub = ActiveSupport::Notifications.subscribe("sql.active_record") { |*, p| queries << p[:sql] if p[:sql] =~ /FROM "opening_hours"/ }
    get "/api/v1/contact_infos"
    ActiveSupport::Notifications.unsubscribe(sub)
    expect(queries.size).to eq(1)
  ensure
    OpeningHour.where(contact_info_id: ContactInfo.where(show_hours: true).where.not(id: [zeta.id, alpha.id])).delete_all
    ContactInfo.where(show_hours: true).where.not(id: [zeta.id, alpha.id]).destroy_all
  end

  it "ignores credentials and is not cacheable" do
    get "/api/v1/contact_infos", headers: { "Authorization" => "Bearer junk" }
    expect(response).to have_http_status(:ok)
    expect(response.headers["Cache-Control"]).to eq("no-store")
  end
end
