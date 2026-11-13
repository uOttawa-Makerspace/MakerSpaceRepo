# frozen_string_literal: true

require "rails_helper"

# The admin home, users, spaces, trainings, training sessions, demotions, skill types and
# university programs pages in French, and the messages after their actions. The English
# wording is pinned by the other admin specs and by the English examples here.
RSpec.describe "Admin area in French", type: :request do
  include SpacesSpecHelpers

  let(:fr) { { locale: "fr" } }
  let!(:admin) { sign_in_as(:admin) }
  let(:space) { create(:space, name: "Makerspace") }
  let(:skill) { create(:skill, name: "Machining") }
  let(:training) { create(:training, name_en: "Laser", name_fr: "Découpe laser", skill:, spaces: [space]) }

  def page_text = Nokogiri::HTML(response.body).text.squish

  around { |example| travel_to(Time.zone.local(2026, 11, 13, 14, 30)) { example.run } }

  it "shows the admin home links in French" do
    get admin_index_path(fr)

    expect(response.body).to include("<title>Paramètres")
    expect(page_text).to include("Paramètres généraux", "Types de compétences", "Gérer les formations", "Gérer les espaces",
                                 "Gérer les rôles", "Dépôts supprimés", "CC non réclamés", "Programmes")
  end

  describe "users" do
    let!(:member) { create(:user, :regular_user, faculty: "Engineering", use: "Prototyping", created_at: 3.days.ago) }

    before do
      create(:lab_session, user: member, space:, sign_in_time: 2.hours.ago, sign_out_time: 2.hours.from_now)
      create(:lab_session, user: member, space:, sign_in_time: 3.days.ago, sign_out_time: 3.days.ago + 1.hour)
    end

    it "lists users with French headings, filters and times" do
      get admin_users_path(fr)

      doc = Nokogiri::HTML(response.body)
      expect(page_text).to include("Gérer les utilisateurs", "Nouveaux utilisateurs", "Afficher les utilisateurs présents",
                                   "Dernière arrivée", "Inscription", "il y a 3 jours")
      expect(doc.css("select#filter option").map { |o| [o.text, o["value"]] })
        .to eq([["Rechercher par...", ""], %w[Nom Name], %w[Courriel Email], ["Nom d'utilisateur", "Username"]])
    end

    it "keeps the English filter labels and times" do
      get admin_users_path

      expect(page_text).to include("Newest users", "Signed in", "3 days ago")
      expect(Nokogiri::HTML(response.body).css("select#filter option").map(&:text)).to eq(["Search by...", "Name", "Email", "Username"])
    end

    it "shows search results in French" do
      get search_admin_users_path(fr.merge(q: member.username, filter: "Username"))

      expect(page_text).to include("Résultats de recherche pour « #{member.username} »", "Modifier", "Voir")

      get search_admin_users_path(fr.merge(q: "nobody-matches"))
      expect(page_text).to include("Aucun résultat")
    end

    it "shows a user's profile and visits in French with French dates" do
      get admin_user_path(member, fr)

      expect(page_text).to include("Présent en ce moment", "Faculté : Engineering", "Utilisation : Prototyping",
                                   "Inscrit le 10 novembre 2026", "Cet utilisateur n'a encore aucune certification.",
                                   "Venu au laboratoire 2 fois", "Temps moyen passé au laboratoire : 90 minutes",
                                   "Visite en cours", "120 min jusqu'à présent", "60 minutes")
    end

    it "keeps the English dates on the profile" do
      get admin_user_path(member)

      expect(page_text).to include("Joined on November 10, 2026", "Been in lab 2 times", "120 min. so far")
    end

    it "labels the edit form and the card choices in French" do
      get edit_admin_user_path(member, fr)

      doc = Nokogiri::HTML(response.body)
      expect(page_text).to include("Modification de l'utilisateur : #{member.username}", "Utilisation", "Carte RFID",
                                   "Changer l'adresse courriel")
      expect(doc.at_css("select#user_rfid option").text).to eq("Aucune")
      expect(doc.at_css("input#new_email")["placeholder"]).to eq("nom@exemple.com")
    end

    it "shows the roles page in French" do
      get manage_roles_admin_users_path(fr)

      expect(page_text).to include("Gérer les rôles", "Administrateurs sur MakerRepo", "Personnel sur MakerRepo", "Bénévoles sur MakerRepo")
      expect(Nokogiri::HTML(response.body).css("input[type=submit]").map { |i| i["value"] }).to include("Changer les espaces", "Appliquer")
    end

    it "reports user changes in French" do
      patch admin_user_path(member, fr), params: { user: { use: "Other" } }
      expect(flash[:notice]).to eq("Les renseignements de l'utilisateur ont été mis à jour")

      patch change_email_admin_user_path(member, fr), params: { new_email: "a@uottawa.ca", confirm_new_email: "b@uottawa.ca" }
      expect(flash[:alert]).to eq("L'adresse de confirmation ne correspond pas à la nouvelle adresse")

      put toggle_lock_user_admin_users_path(fr), params: { id: member.id }
      expect(flash[:notice]).to eq("Utilisateur verrouillé!")

      patch rename_user_admin_users_path(fr), params: { id: member.id }
      expect(flash[:alert]).to eq("Aucun nom d'utilisateur fourni")
    end
  end

  describe "spaces" do
    before do
      create(:sub_space, space:, name: "Room A", approval_required: true)
      create(:training_session, training:, space:)
    end

    it "shows the space list and the space page in French" do
      get admin_spaces_path(fr)
      expect(page_text).to include("Gestion des espaces", "Choisissez un espace à modifier")
      expect(Nokogiri::HTML(response.body).css("input[type=submit], button").map { |b| b["value"] || b.text.strip })
        .to include("Modifier Makerspace", "Créer")

      get edit_admin_space_path(space, fr)
      doc = Nokogiri::HTML(response.body)
      expect(page_text).to include("Capacité maximale", "Gérer les lecteurs RFID", "Lecteurs RFID de Makerspace",
                                   "Formations de Makerspace", "Sous-espaces", "Supprimer l'espace",
                                   "Tapez MAKERSPACE dans la case, puis cliquez sur SUPPRIMER :")
      expect(doc.css("button").map { |b| b.text.strip }).to include("Activer l'approbation automatique des réservations", "Rendre public par défaut")
      expect(doc.css("select[name='staff_needed_calendar_role[]'] option").map { |o| [o.text, o["value"]] }.uniq)
        .to eq([["Aucun rôle", ""], ["Heures d'ouverture", "open_hours"]])
    end

    it "reports space changes in French" do
      room = SubSpace.find_by!(name: "Room A")
      post admin_space_change_sub_space_default_public_path(fr.merge(space_id: space.id, id: room.id))
      expect(flash[:notice]).to eq("Les réservations dans Room A sont publiques par défaut")

      patch admin_space_update_sub_space_path(fr.merge(space_id: space.id, id: room.id)), params: { name: "Room Z" }
      expect(flash[:notice]).to eq("« Room A » a été renommé « Room Z »."), flash.inspect

      patch add_space_manager_admin_spaces_path(fr), params: { space_id: space.id, space_manager_id: -1 }
      expect(flash[:alert]).to eq("Veuillez choisir un administrateur")

      post update_max_capacity_admin_spaces_path(fr), params: { space_id: space.id, max_capacity: 9 }
      expect(flash[:notice]).to eq("La capacité de l'espace a été mise à jour!")
    end

    it "keeps the English sub space messages" do
      room = SubSpace.find_by!(name: "Room A")
      put admin_space_change_sub_space_approval_path(space_id: space.id, id: room.id)

      expect(flash[:alert]).to eq("Please add contact information for the associated space disabling automatic booking.")
    end
  end

  describe "trainings, sessions and demotions" do
    let(:trainer) { create(:user, :staff, name: "Trainer One") }
    let!(:training_session) { create(:training_session, training:, space:, user: trainer, level: "Beginner") }

    it "shows the trainings pages in French" do
      get admin_trainings_path(fr)
      expect(page_text).to include("Gestion des formations", "Nouvelle formation", "Type de compétence", "Modifier", "Supprimer")

      get edit_admin_training_path(training, fr)
      expect(page_text).to include("Modification de la formation Découpe laser", "Liste des compétences")
      expect(Nokogiri::HTML(response.body).at_css("input[type=submit]")["value"]).to eq("Mettre à jour la formation")
    end

    it "shows the training sessions with French filters and dates" do
      get admin_training_sessions_path(fr)

      doc = Nokogiri::HTML(response.body)
      expect(page_text).to include("Gestion des séances de formation", "Filtrer par période :", "13 novembre 2026 à 14:30",
                                   "NON TERMINÉE", "Affichage de 1 à 1 sur 1")
      expect(doc.css("select#date_range option").first(3).map { |o| [o.text, o["value"]] })
        .to eq([["30 derniers jours", "30_days"], ["90 derniers jours", "90_days"], ["Dernière année", "1_year"]])
    end

    it "keeps the English session date" do
      get admin_training_sessions_path

      expect(page_text).to include("November 13, 2026 14:30", "Displaying 1 - 1 of 1")
    end

    it "shows the demotions and their messages in French" do
      demoted = create(:certification, user: create(:user, :regular_user), training_session:, training:,
                                       active: false, demotion_reason: "Unsafe")
      get demotions_admin_certifications_path(fr)
      expect(page_text).to include("Rétrogradations", "Raison de la rétrogradation", "13 novembre 2026", "Membre du personnel inconnu")

      delete admin_certification_path(demoted, fr)
      expect(flash[:notice]).to eq("La certification a été supprimée. Cette action est irréversible")

      delete admin_training_session_path(training_session, fr)
      expect(flash[:notice]).to eq("La séance a été supprimée")
    end
  end

  describe "skill types and programs" do
    it "shows the skill pages and messages in French" do
      skill
      get admin_skills_path(fr)
      expect(page_text).to include("Gestion des types de compétences", "Type de compétence", "Modifier")

      post admin_skills_path(fr), params: { name: "Welding" }
      expect(flash[:notice]).to eq("Le type de compétence a été ajouté!")

      get edit_admin_skill_path(Skill.find_by!(name: "Welding"), fr)
      expect(page_text).to include("Modification de Welding", "Type de compétence :", "Retour")
    end

    it "shows the programs page and the import summary in French" do
      create(:uni_program, program: "Biology", faculty: "Science", department: "Bio", level: "Graduate")
      get admin_uni_programs_index_path(fr)
      expect(page_text).to include("Programmes Universitaires", "Permettre l'ajout de nouvelles facultés", "Science - 1 programmes")

      file = Rack::Test::UploadedFile.new(StringIO.new("program,level,faculty,department\nBiology,Graduate,Science,Bio\n"),
                                          "text/csv", original_filename: "programs.csv")
      post admin_uni_programs_import_programs_path(fr), params: { file: }
      expect(flash[:notice]).to eq("Téléversement terminé, 1 programmes trouvés (0 ajoutés, 0 mis à jour, 0 restaurés, 0 retirés)")
    end
  end
end
