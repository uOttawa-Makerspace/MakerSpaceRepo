# frozen_string_literal: true

require "rails_helper"

# The learning area in French: page wording, level and status names, messages
# after an action, and the skills track page. The English wording is pinned by
# the other learning area specs and by the English examples here.
RSpec.describe "Learning area in French", type: :request do
  include ActiveJob::TestHelper

  let(:training) { create(:training, name_en: "Laser", name_fr: "Découpe laser") }
  let!(:beginner) { create(:learning_module, training:, title: "Plain one", level: "Beginner") }
  let!(:advanced) { create(:learning_module, training:, title: "Adv one", level: "Advanced") }
  let(:fr) { { locale: "fr" } }

  def page_text = Nokogiri::HTML(response.body).text.squish

  def packaged(title, status, changed_at: Time.current)
    create(:learning_module, :with_scorm_object, training:, title:).tap do |lm|
      lm.update_columns(scorm_status: LearningModule.scorm_statuses[status], scorm_status_changed_at: changed_at)
    end
  end

  describe "the module list" do
    it "shows headings, level names, progress counts and the admin tools in French" do
      create(:learning_module, training:, title: "Sub one", level: "Intermediate", subskill: "Cutting")
      sign_in_as(:admin)
      get learning_area_index_path(fr)

      expect(response.body).to include("<title>Zone d&#39;apprentissage")
      expect(page_text).to include("Modules d'apprentissage", "Suivez votre progression dans tous les domaines de formation",
                                   "Nouveau module d'apprentissage", "0 sur 3 terminé(s)", "Haut de page",
                                   "Sous-compétences", "0 / 1 débutant", "0 / 1 avancé", "Débutant 0 sur 1 terminé(s)",
                                   "Réordonner", "Modifier")
      expect(page_text).not_to include("completed", "Re-order", "Subskills")
    end

    it "keeps the English wording and level names" do
      sign_in_as(:regular)
      get learning_area_index_path

      expect(page_text).to include("Learning Modules", "0 of 2 completed", "0 / 1 beginner", "Beginner 0 of 1 completed",
                                   "Advanced 0 of 1 completed")
    end

    it "labels a module's status in French" do
      user = sign_in_as(:regular)
      create(:learning_module_track, :completed, user:, learning_module: advanced)
      get learning_area_index_path(fr)

      status = Nokogiri::HTML(response.body).at_css("[role=status][aria-label='Statut : Complète']")
      expect(status&.text&.strip).to eq("Complète")
    end
  end

  describe "a module page" do
    it "offers to start a module that is not begun" do
      sign_in_as(:regular)
      get learning_area_path(beginner, fr)

      expect(page_text).to include("Débutant", "Prêt à commencer?", "Vous n'avez pas encore commencé ce module.")
      expect(Nokogiri::HTML(response.body).at_css("form[action*='start'] button").text).to eq("Commencer le module")
    end

    it "offers to mark a module in progress as completed, and praises a completed one" do
      user = sign_in_as(:regular)
      create(:learning_module_track, user:, learning_module: beginner)
      create(:learning_module_track, :completed, user:, learning_module: advanced)

      get learning_area_path(beginner, fr)
      expect(page_text).to include("En cours", "Marquez ce module comme terminé lorsque vous aurez fini.", "Marquer comme terminé")

      get learning_area_path(advanced, fr)
      expect(page_text).to include("Avancé", "Vous avez terminé ce module — beau travail!")
    end

    it "lists project files with their size in French units" do
      beginner.project_files.attach(io: StringIO.new("a" * 1500), filename: "notes.pdf")
      sign_in_as(:regular)
      get learning_area_path(beginner, fr)

      expect(page_text).to include("Fichiers du projet", "notes.pdf 1.5 Ko")
    end

    it "explains a package that is still being extracted" do
      sign_in_as(:regular)
      get learning_area_path(packaged("Packaged", :pending), fr)

      expect(page_text).to include("Chargement...", "Le paquet SCORM est en traitement",
                                   "Cette page se mettra à jour automatiquement dès qu'il sera prêt.")
    end

    it "gives staff the reason a package failed and an admin the retry, and tells a member to come back later" do
      failed = packaged("Broken", :failed)
      sign_in_as(:admin)
      get learning_area_path(failed, fr)
      expect(page_text).to include("L'extraction SCORM a échoué", "Le paquet n'a pas pu être traité.",
                                   "SCORM 1.2 ou 2004 valide contenant un fichier imsmanifest.xml")
      expect(Nokogiri::HTML(response.body).at_css("form[action*='retry_scorm'] button").text).to eq("Relancer l'extraction")

      reset!
      sign_in_as(:regular)
      get learning_area_path(failed, fr)
      expect(page_text).to include("Ce module n'est pas encore disponible. Veuillez revenir plus tard.")
    end

    it "names a stalled extraction in French" do
      sign_in_as(:staff)
      get learning_area_path(packaged("Stuck", :processing, changed_at: 1.hour.ago), fr)

      expect(page_text).to include("L'extraction SCORM est bloquée",
                                   "L'extraction ne s'est pas terminée. Le processus d'arrière-plan n'est peut-être pas en marche.")
    end

    it "shows the player controls of a ready package in French" do
      ready = create(:learning_module, :with_scorm_object, training:, title: "Ready", shortcut_name: "ready_one")
      ExtractScormJob.perform_now(ready.id)
      sign_in_as(:regular)
      get learning_area_path(ready, fr)

      expect(page_text).to include("Copier le lien permanent", "Plein écran",
                                   "Le module est ouvert dans un autre onglet. Fermez-le pour continuer ici.")
    end

    it "translates the back link of a subskill page" do
      create(:learning_module, training:, title: "Sub one", subskill: "Cutting")
      sign_in_as(:regular)
      get subskill_learning_area_index_path("Cutting", fr)

      expect(Nokogiri::HTML(response.body).at_css("a.btn-outline-secondary").text).to eq("Retour")
    end
  end

  describe "the module form" do
    before { sign_in_as(:admin) }

    it "labels the new module form in French with the level keys as option values" do
      get new_learning_area_path(fr)

      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css("h1").text).to eq("Nouveau module d'apprentissage")
      expect(doc.at_css("label[for=repository_title]").text).to eq("Titre")
      expect(doc.at_css("#repository_title")["placeholder"]).to eq("Titre du module d'apprentissage…")
      expect(doc.at_css("#learning_module_shortcut_name")["title"]).to eq("Lettres, chiffres et traits de soulignement seulement")
      expect(doc.css("#learning_module_level option").map { |o| [o.text, o["value"]] })
        .to eq([%w[Général general], %w[Débutant beginner], %w[Intermédiaire intermediate], %w[Avancé advanced]])
      expect(doc.at_css("#learning_module_subskill option[value='']").text).to eq("Choisissez ou entrez une nouvelle sous-compétence...")
      submit = doc.at_css("#waiting-save-button")
      expect([submit["value"], submit["data-turbo-submits-with"]]).to eq(["Créer le module d'apprentissage", "Enregistrement (veuillez patienter)..."])
      expect(page_text).to include("Glissez-déposez les fichiers ici", "Paquet SCORM (.zip)", "Galerie", "Vidéos")
    end

    it "shows the English level names with the level keys as option values" do
      get new_learning_area_path

      expect(Nokogiri::HTML(response.body).css("#learning_module_level option").map { |o| [o.text, o["value"]] })
        .to eq([%w[General general], %w[Beginner beginner], %w[Intermediate intermediate], %w[Advanced advanced]])
    end

    it "shows the package status and the current package link on the edit page" do
      ready = create(:learning_module, :with_scorm_object, training:, title: "Ready")
      ExtractScormJob.perform_now(ready.id)
      get edit_learning_area_path(ready, fr)

      expect(page_text).to include("Modifier le module d'apprentissage", "Statut du paquet SCORM : Prêt",
                                   "Télécharger le paquet SCORM actuel : #{ready.scorm_package.filename}")
      expect(Nokogiri::HTML(response.body).at_css("#waiting-save-button")["value"]).to eq("Enregistrer les modifications")
    end
  end

  describe "messages after an action" do
    it "reports create, update, reorder, retry and delete in French" do
      sign_in_as(:admin)
      post learning_area_index_path(fr), params: { learning_module: { title: "New lm", training_id: training.id, level: "Beginner" } }
      expect(flash[:notice]).to eq("Le module d'apprentissage a été créé.")

      patch learning_area_path(beginner, fr), params: { learning_module: { title: "Renamed" } }
      expect(flash[:notice]).to eq("Le module d'apprentissage a été modifié.")

      put reorder_learning_area_index_path(fr), params: { data: [advanced.id, beginner.id] }
      expect(flash[:notice]).to eq("Les modules d'apprentissage ont été réordonnés!")

      failed = packaged("Broken", :failed)
      post retry_scorm_learning_area_path(failed, fr)
      expect(flash[:notice]).to eq("L'extraction SCORM a été remise en file d'attente.")
      post retry_scorm_learning_area_path(beginner, fr)
      expect(flash[:alert]).to eq("L'extraction SCORM ne peut pas être relancée pour le moment.")

      delete learning_area_path(advanced, fr)
      expect(flash[:notice]).to eq("Le module d'apprentissage a été supprimé.")
    end

    it "reports starting and completing a module in French" do
      sign_in_as(:regular)
      post start_learning_module_track_index_path(fr), params: { learning_module_id: beginner.id }
      expect(flash[:notice]).to eq("Vous avez commencé le module d'apprentissage!")

      post completed_learning_module_track_index_path(fr), params: { learning_module_id: beginner.id }
      expect(flash[:notice]).to eq("Vous avez terminé le module d'apprentissage!")

      post completed_learning_module_track_index_path(fr), params: { learning_module_id: 0 }
      expect(flash[:alert]).to eq("Ce module d'apprentissage est introuvable.")

      post completed_learning_module_track_index_path(fr), params: { learning_module_id: packaged("Pkg", :ready).id }
      expect(flash[:alert]).to eq("Ce module d'apprentissage indique lui-même quand il est terminé.")
    end

    it "names the shortcut field in a French validation message" do
      sign_in_as(:admin)
      post learning_area_index_path(fr),
           params: { learning_module: { title: "Dup", training_id: training.id, level: "Beginner", shortcut_name: beginner.shortcut_name } }

      expect(flash[:alert]).to start_with("Le module d'apprentissage n'a pas été créé. Lien abrégé ")
    end
  end

  describe "the skills track page" do
    let!(:skill) { create(:skill, name: "Fabrication") }

    before { training.update!(skill:) }

    { "en" => ["Skills", "Beg", "Modules finished : 0 / 2", "Next modules to complete :", "None"],
      "fr" => ["Compétences", "Déb", "Modules terminés : 0 / 2", "Prochains modules à terminer :", "Aucune"] }
      .each do |locale, wording|
        it "shows progress, the next level and an uncertified training (#{locale})" do
          sign_in_as(:regular)
          get learning_module_track_index_path(locale:)

          expect(page_text).to include(*wording)
        end
      end

    it "shows the highest remaining level as master once every module is completed" do
      user = sign_in_as(:regular)
      [beginner, advanced].each { |lm| create(:learning_module_track, :completed, user:, learning_module: lm) }
      get learning_module_track_index_path(fr)

      expect(Nokogiri::HTML(response.body).at_css("p[style='float: right'] span").text).to eq("Maître")
    end
  end
end
