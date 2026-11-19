# frozen_string_literal: true

require "rails_helper"

# The admin pages for announcements, contact infos, Design Day, drop-off locations, keys, key
# transactions, membership tiers, settings, teams, time periods, adding staff, deleted repositories,
# unclaimed CC money and the job order settings forms show their wording, and the messages after
# their actions, in the admin's language.
RSpec.describe "Admin area pages in French", type: :request do
  let(:space) { create(:space, name: "Makerspace", keycode: "MKS") }

  def sign_in_admin(locale)
    admin = create(:user, :admin, locale: locale)
    post login_authentication_path, params: { username_email: admin.username, password: "asa32A353#" }
    admin
  end

  def page_text
    Nokogiri::HTML(response.body).at("body").text.squish
  end

  context "when the admin reads French" do
    let!(:admin) { sign_in_admin("fr") }

    it "shows the announcement list, its audience and state in French" do
      create(:announcement, user: admin, description: "Fermé lundi", public_goal: "staff")

      get admin_announcements_path

      expect(page_text).to include("Annonces", "Nouvelle annonce", "Date de soumission", "Personnel", "Oui", "Masquée par : Personne")
      expect(page_text).not_to include("Dismissed by")
    end

    it "shows the announcement form in French with the same radio labels" do
      get new_admin_announcement_path

      doc = Nokogiri::HTML(response.body)
      expect(doc.at("label[for='announcement_public_goal_regular_user']").text).to eq("Tous les utilisateurs")
      expect(page_text).to include("Créer une annonce", "Effacer la date de fin")
    end

    it "shows the key pages in French, keeping the stored values" do
      key = create(:key, :keycard_key_type, :inventory_status, number: 7, custom_keycode: "KC7", additional_info: "")

      get admin_keys_path
      expect(page_text).to include("Gestion des clés", "Toutes les clés", "Carte d'accès", "En inventaire", "(personnel)", "(superviseur)")

      get new_admin_key_path
      doc = Nokogiri::HTML(response.body)
      expect(doc.css("#key-type-select option").map { |o| [o.text, o["value"]] }).to include(["Passe partiel", "sub_master"])

      get admin_key_path(key)
      expect(page_text).to include("Clé n° 7 - En inventaire", "Renseignements sur la clé")
    end

    it "shows the key transactions, teams, time periods and settings pages in French" do
      get admin_key_transactions_path
      expect(page_text).to include("Transactions de clés", "En attente du remboursement du dépôt")

      team = Team.create!(name: "Fusée")
      captain = create(:user, :regular_user)
      TeamMembership.create!(team: team, user: captain, role: :captain)
      get admin_team_path(team)
      expect(page_text).to include("Membres de l'équipe", "Capitaine")

      get admin_time_periods_path
      expect(page_text).to include("Aucune période n'a encore été créée.")

      JobOrderMessage.create!(name: "processed", message: "x")
      JobOrderMessage.print_failed
      get admin_settings_path
      expect(page_text).to include("Ajouter une catégorie", "Retirer un lecteur de cartes", "Cours")
    end

    it "shows the contact info form with French day names" do
      info = create(:contact_info, name: "Makerspace")
      info.opening_hours.create!(target_en: "Students", target_fr: "Étudiants")

      get edit_admin_contact_info_path(info)

      expect(page_text).to include("Modifier les coordonnées", "Lundi", "Marquer pour suppression?")
    end

    it "shows the Design Day page in French" do
      create(:design_day)

      get admin_design_day_path

      expect(page_text).to include("Plans d'étage affichés")
    end

    it "shows the job order settings forms in French" do
      get new_admin_job_type_path
      expect(page_text).to include("Nouveau type de commande", "Accepter plusieurs fichiers")

      get new_admin_job_service_group_path
      expect(page_text).to include("Accepter une saisie de texte")
    end

    it "shows the drop-off, membership, staff, deleted repository and CC money pages in French" do
      get admin_drop_off_locations_path
      expect(page_text).to include("Gestion des lieux de dépôt")
      get admin_memberships_path
      expect(page_text).to include("Niveaux d'adhésion", "Durée (jours)")
      get admin_add_new_staff_index_path
      expect(page_text).to include("Espaces assignés", "Confirmer les changements")
      get admin_deleted_repositories_path
      expect(page_text).to include("Aucun dépôt n'a été supprimé.")
      get admin_cc_moneys_path
      expect(page_text).to include("CC non réclamés")
    end

    it "gives the action messages in French" do
      post admin_drop_off_locations_path, params: { name: "" }
      expect(flash[:alert]).to eq("La saisie est invalide")

      post add_category_admin_settings_path, params: { category_option: { name: "Bois" } }
      expect(flash[:notice]).to eq("Catégorie ajoutée!")

      post admin_teams_path, params: { team: { name: "T1" } }
      expect(flash[:alert]).to eq("Veuillez choisir un capitaine")

      get admin_key_path(0)
      expect(flash[:alert]).to eq("Cette clé est introuvable.")

      post admin_time_periods_path, params: { time_period: { name: "Hiver", start_date: "2026-01-05", end_date: "2026-04-20" } }
      expect(flash[:notice]).to eq("La nouvelle période a été créée!")
    end

    it "names the audience of a new announcement in French" do
      post admin_announcements_path, params: { announcement: { description: "Bonjour", public_goal: "regular_user", active: true } }

      expect(flash[:notice]).to eq("Vous avez créé une annonce pour : Tous les utilisateurs")
    end

    it "names an unapproved holder in French on the assign form" do
      key = create(:key, :regular_key_type, :inventory_status, space: space)
      create(:user, :staff, name: "Sam Staff")

      get admin_key_assign_path(key)

      expect(page_text).to include("Sam Staff (aucun formulaire de demande)")
    end
  end

  context "when the admin reads English" do
    before { sign_in_admin("en") }

    it "keeps the English wording" do
      create(:announcement, description: "Hi", public_goal: "regular_user", active: false)

      get admin_announcements_path
      expect(page_text).to include("Dismissed by: No one", "All Users", "No")

      post admin_announcements_path, params: { announcement: { description: "Hi all", public_goal: "regular_user", active: true } }
      expect(flash[:notice]).to eq("You've successfully created an announcement for All Users")

      post admin_drop_off_locations_path, params: { name: "Desk" }
      expect(flash[:notice]).to eq("Drop-off Location added successfully!")
    end
  end
end
