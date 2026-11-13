# frozen_string_literal: true

require "rails_helper"

# The volunteer area (tasks, task requests, hours, shadowing shifts, lists and stats) in French,
# with English dates and wording unchanged.
RSpec.describe "Volunteer area in French", type: :request do
  let(:makerspace) { create(:space, name: "Makerspace") }
  let(:staff) { create(:user, :staff, name: "Sam Staff") }
  let(:volunteer) { create(:user, :volunteer_with_volunteer_program, name: "Val Volunteer") }
  let(:training) { create(:training, name_en: "Laser Cutter", name_fr: "Découpeuse laser") }
  let!(:task) do
    create(:volunteer_task, title: "setup crew", space: makerspace, joins: 3, cc: 7, hours: 2, category: "Events")
  end

  around { |example| travel_to(Time.zone.local(2026, 11, 3, 14, 30)) { example.run } }

  before do
    RequireTraining.create!(volunteer_task: task, training: training)
    VolunteerTaskJoin.create!(volunteer_task: task, user: volunteer, user_type: "Volunteer", state: "joined", active: true)
  end

  def text = Nokogiri::HTML(response.body).text.squish

  describe "as staff" do
    before { vol_login!(staff) }

    it "shows the task list, categories and task page in French" do
      get volunteer_tasks_path(locale: "fr")
      expect(text).to include("Tâches disponibles", "Événements", "Préalables :", "Voir les détails", "7 CC", "2.0 h")
      expect(text).to include("gagnez des Crédits du CGEC (CC)")
      expect(text).not_to include("Available Tasks", "View Details", "communautaires")

      get volunteer_task_path(task, locale: "fr")
      expect(text).to include("Aperçu de la tâche", "2.0 heures", "Capacité : 3", "Découpeuse laser", "En cours (1 assigné(s))")
    end

    it "lets the task search find a task by its category in the page language" do
      get volunteer_tasks_path(locale: "fr")
      search = Nokogiri::HTML(response.body).at_css(".task-item-card-col")["data-searchable-text"]
      expect(search).to include("events", "événements")

      get volunteer_tasks_path(locale: "en")
      expect(Nokogiri::HTML(response.body).at_css(".task-item-card-col")["data-searchable-text"]).to start_with("setup crew events makerspace")
      expect(text).to include("earn CEED Credits (CCs)")
      expect(text).not_to include("Community Credits")
    end

    it "labels the category and certification choices of the task form in French and submits the stored names" do
      get new_volunteer_task_path(locale: "fr")
      page = Nokogiri::HTML(response.body)

      expect(page.at_css('select#volunteer_task_category option[value="Events"]').text).to eq("Événements")
      expect(page.at_css("select#task_certifications option").text).to eq("Découpeuse laser")
      expect(text).to include("Créer une tâche de bénévolat", "Choisir un espace...")
    end

    it "writes task request dates in French order and English order" do
      create(:volunteer_task_request, volunteer_task: task, user: volunteer, approval: nil)

      get volunteer_task_requests_path(locale: "fr")
      expect(text).to include("En attente de révision", "3 nov. 2026", "14:30", "Refuser")

      get volunteer_task_requests_path(locale: "en")
      expect(text).to include("Pending Review", "Nov 03, 2026", "02:30 PM", "Deny")
    end

    it "shows shadowing shifts with French weekday dates and 24-hour times" do
      ShadowingHour.create!(user: volunteer, space: makerspace, event_id: "e1",
                            start_time: Time.zone.local(2026, 11, 5, 9), end_time: Time.zone.local(2026, 11, 5, 12))

      get shadowing_shifts_volunteers_path(locale: "fr")
      expect(text).to include("Périodes d'observation", "jeudi 5 novembre 2026", "09:00 – 12:00", "Annuler la période")

      get shadowing_shifts_volunteers_path(locale: "en")
      expect(text).to include("Thursday, November 05, 2026", "9:00 AM – 12:00 PM", "Cancel Shift")
    end

    it "shows the hour requests, email lists, directory and calendar pages in French" do
      create(:volunteer_hour, user: volunteer, volunteer_task: task, total_time: 1.5, approval: nil)

      get volunteer_hour_requests_volunteer_hours_path(locale: "fr")
      expect(text).to include("Demandes d'heures de bénévolat", "03/11/2026 (nov.)", "1.5 heures")

      get emails_volunteers_path(locale: "fr")
      expect(text).to include("Listes de courriels des bénévoles", "Copier tous les courriels")

      get volunteer_list_volunteers_path(locale: "fr")
      expect(text).to include("Répertoire des bénévoles", "Tâches actives")

      get calendar_volunteers_path(locale: "fr")
      expect(text).to include("Calendrier d'observation", "Centre Brunsfield")

      get new_event_volunteers_path(locale: "fr")
      expect(text).to include("Nouvelle période d'observation", "Heure de début")
    end

    it "gives the hour date cells an ISO sort key so French dates sort by date" do
      create(:volunteer_hour, user: volunteer, volunteer_task: task, total_time: 1.5, approval: nil, date_of_task: Date.new(2026, 10, 30))
      create(:volunteer_hour, user: volunteer, volunteer_task: task, total_time: 2, approval: true, date_of_task: Date.new(2026, 10, 29))

      get volunteer_hour_requests_volunteer_hours_path(locale: "fr")
      keys = Nokogiri::HTML(response.body).css("td[data-sort-as]").map { |td| td["data-sort-as"] }

      expect(keys).to include(Time.zone.local(2026, 11, 3, 14, 30).iso8601, Time.zone.local(2026, 10, 30).iso8601,
                              Time.zone.local(2026, 10, 29).iso8601)
      expect(text).to include("30/10/2026 (oct.)")
    end

    it "gives the task request flash in French" do
      request = create(:volunteer_task_request, volunteer_task: task, user: volunteer, approval: nil)

      put update_approval_volunteer_task_requests_path(id: request.id, approval: false, locale: "fr")
      expect(flash[:notice]).to eq("Demande de tâche mise à jour")
    end
  end

  describe "as a volunteer" do
    before { vol_login!(volunteer) }

    it "shows my tasks, my stats and my hours in French" do
      get my_tasks_volunteer_tasks_path(locale: "fr")
      expect(text).to include("Mes tâches assignées", "Soumettre comme terminée", "3 nov. 2026")

      get my_stats_volunteers_path(locale: "fr")
      expect(text).to include("Mes statistiques de bénévolat", "Prochain niveau : Débutant", "1 parcours")

      create(:volunteer_hour, user: volunteer, volunteer_task: task, total_time: 2, approval: true)
      get volunteer_hours_path(locale: "fr")
      expect(text).to include("Heures de bénévolat de Val Volunteer", "Approuvée", "Traitée")
    end

    it "gives the dates of my hours an ISO sort key" do
      create(:volunteer_hour, user: volunteer, volunteer_task: task, total_time: 2, approval: nil, date_of_task: Date.new(2026, 10, 30))

      get volunteer_hours_path(locale: "fr")
      keys = Nokogiri::HTML(response.body).css("td[data-sort-as]").map { |td| td["data-sort-as"] }
      expect(keys).to eq([Time.zone.local(2026, 11, 3, 14, 30).iso8601, Time.zone.local(2026, 10, 30).iso8601])
    end

    it "sends a task for review with the confirmation in French" do
      post create_request_volunteer_task_requests_path(id: task.id, locale: "fr")
      expect(flash[:notice]).to eq("Votre demande a été envoyée. Vous n'avez rien d'autre à faire.")
    end

    it "refuses a staff page with the message in French" do
      get new_volunteer_task_path(locale: "fr")
      expect(flash[:alert]).to eq("Vous ne pouvez pas accéder à cette zone.")
    end
  end
end
