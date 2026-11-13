# frozen_string_literal: true

require "rails_helper"

# The staff dashboard pages and their messages follow the chosen language. The staff app's
# JSON keeps its English error text in either language.
RSpec.describe "Staff dashboard in French", type: :request do
  include StaffDashboardSpecHelpers

  let!(:space) { create(:space, name: "Makerspace", max_capacity: 1) }
  let!(:staff) { sign_in_as(:staff, space: space) }
  let!(:visitor) { create(:user, :regular_user, name: "Alpha Visitor", username: "alphavisitor") }

  before { sign_in_session(visitor, space) }

  def page_text = Nokogiri::HTML(response.body).text.squish

  it "shows the dashboard headings, buttons and table columns in French" do
    get staff_dashboard_index_path, params: { locale: "fr" }

    expect(response).to have_http_status(:ok)
    expect(page_text).to include(
      "Bienvenue à", "1 utilisateur dans Makerspace", "Gérer les imprimantes 3D",
      "Enregistrer le départ de tous les utilisateurs", "Certifications dans Makerspace",
      "Utilisateurs récemment partis de Makerspace", "Nouveaux utilisateurs inscrits sur MakerRepo",
      "Recherche avancée et enregistrement", "Arrivée d'un utilisateur", "Aucun"
    )
    expect(page_text).not_to include("Welcome to", "Sign Out All Users", "Last Seen")
  end

  it "listens for table updates on the stream of its own language" do
    get staff_dashboard_index_path, params: { locale: "fr" }
    french = Turbo::StreamsChannel.signed_stream_name(StaffDashboardChannel.table_stream(space.id, :fr))

    expect(Nokogiri::HTML(response.body).css("turbo-cable-stream-source").pluck("signed-stream-name")).to eq([french])
  end

  it "names the previous visit in French" do
    returning = create(:user, :regular_user)
    create(:lab_session, user: returning, space: space, sign_in_time: 3.hours.ago, sign_out_time: 61.minutes.ago)
    sign_in_session(returning, space)

    get staff_dashboard_index_path, params: { locale: "fr" }

    expect(page_text).to include("il y a environ une heure à Makerspace")
  end

  it "shows search results in French" do
    get staff_dashboard_search_path, params: { query: "Alpha", locale: "fr" }

    expect(page_text).to include("Résultats de recherche", "Présent", "Utilisateurs dans Makerspace : 1")
  end

  it "says the space is full in French" do
    get staff_dashboard_refresh_capacity_path, params: { locale: "fr" }

    expect(page_text).to include("La capacité maximale de l'espace est atteinte!",
                                 "Il y a actuellement 1 personnes et la capacité maximale est de 1 personnes.")
  end

  it "escapes the over-capacity alert for its script" do
    sign_in_session(create(:user, :regular_user), space)

    get staff_dashboard_refresh_capacity_path, params: { locale: "fr" }

    expect(response.body).to include(%{alert("L\\'espace DÉPASSE sa capacité maximale.})
  end

  it "gives the flash messages in French" do
    get staff_dashboard_user_profile_path, params: { locale: "fr" }
    expect(flash[:alert]).to eq("Sélectionnez un utilisateur valide")

    get staff_dashboard_search_path, params: { locale: "fr" }
    expect(flash[:alert]).to eq("Aucun critère de recherche.")

    put staff_dashboard_sign_out_users_path, params: { dropped_users: ["nobody-here"], locale: "fr" }
    expect(flash[:alert]).to eq("Nom d'utilisateur inconnu : nobody-here")
  end

  it "keeps the staff app's JSON error text in English" do
    put staff_dashboard_change_space_path(format: :json), params: { space_id: 0, locale: "fr" }

    expect(response).to have_http_status(:not_found)
    expect(json).to eq("status" => "error", "error" => "Space not found")
  end
end
