# frozen_string_literal: true

require "rails_helper"

# The admin screens answer a refused write with a sentence that names what was not saved followed by
# the record's validation messages (or, for a delete the database refuses, that the record is in use).
RSpec.describe "Admin error messages", type: :request do
  include SpacesSpecHelpers

  before { sign_in_as(:admin) }

  # Makes the next write on the model's records fail with a validation message.
  def refuse_writes(model, *methods)
    methods.each do |name|
      allow_any_instance_of(model).to receive(name) do |record|
        record.errors.add(:base, "Refused for the spec")
        false
      end
    end
  end

  describe "time periods" do
    let!(:period) { create(:time_period) }

    it "names the failed create and shows the validation message" do
      post admin_time_periods_path, params: { time_period: { name: "", start_date: "2028-01-05", end_date: "2028-04-20" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(flash[:alert]).to start_with("The time period was not created. ")
    end

    it "names the failed update in English and French" do
      patch admin_time_period_path(period), params: { time_period: { end_date: "2000-01-01" } }
      expect(flash[:alert]).to eq("The time period was not updated. End date must not be before the start date")
      patch admin_time_period_path(period), params: { time_period: { end_date: "2000-01-01" }, locale: "fr" }
      expect(flash[:alert]).to start_with("La période n'a pas été modifiée. ")
    end

    it "names the failed delete" do
      refuse_writes(TimePeriod, :destroy)
      delete admin_time_period_path(period)
      expect(flash[:alert]).to eq("The time period was not deleted. Refused for the spec")
    end
  end

  describe "contact infos" do
    let!(:info) { create(:contact_info) }

    it "names the failed update and delete" do
      refuse_writes(ContactInfo, :update, :destroy)
      patch admin_contact_info_path(info), params: { contact_info: { email: "x@example.com" } }
      expect(flash[:alert]).to eq("The contact information was not updated. Refused for the spec")
      delete admin_contact_info_path(info)
      expect(flash[:alert]).to eq("The contact information was not deleted. Refused for the spec")
    end

    it "answers in French" do
      refuse_writes(ContactInfo, :update)
      patch admin_contact_info_path(info), params: { contact_info: { email: "x@example.com" }, locale: "fr" }
      expect(flash[:alert]).to eq("Les coordonnées n'ont pas été modifiées. Refused for the spec")
    end
  end

  describe "announcements" do
    let!(:announcement) { create(:announcement) }

    it "names the failed update and delete" do
      refuse_writes(Announcement, :update, :destroy)
      patch admin_announcement_path(announcement), params: { announcement: { description: "x" } }
      expect(flash[:alert]).to eq("The announcement was not updated. Refused for the spec")
      delete admin_announcement_path(announcement)
      expect(flash[:alert]).to eq("The announcement was not deleted. Refused for the spec")
    end

    it "answers in French" do
      refuse_writes(Announcement, :destroy)
      delete admin_announcement_path(announcement), params: { locale: "fr" }
      expect(flash[:alert]).to eq("L'annonce n'a pas été supprimée. Refused for the spec")
    end
  end

  describe "training sessions" do
    let!(:session_record) { create(:training_session) }

    it "names the failed update in English and French" do
      patch admin_training_session_path(session_record), params: { training_session: { user_id: create(:user, :regular_user).id } }
      expect(flash[:alert]).to eq("The training session was not updated. User must be staff")
      patch admin_training_session_path(session_record),
            params: { training_session: { user_id: create(:user, :regular_user).id }, locale: "fr" }
      expect(flash[:alert]).to start_with("La séance de formation n'a pas été modifiée. ")
    end

    it "says the session is in use when a record still points at its certifications" do
      create(:proficient_project_session, level: "Beginner", certification: create(:certification, training_session: session_record))
      delete admin_training_session_path(session_record)
      expect(flash[:alert]).to eq(
        "The training session was not deleted. Other records still use it, so it was left as it is."
      )
      expect(TrainingSession.exists?(session_record.id)).to be(true)
    end
  end

  describe "certifications" do
    let!(:certification) { create(:certification) }

    it "names the failed update and delete" do
      refuse_writes(Certification, :update)
      patch admin_certification_path(certification), params: { certification: { active: false } }
      expect(flash[:alert]).to eq("The certification was not updated. Refused for the spec")
      refuse_writes(Certification, :destroy)
      delete admin_certification_path(certification)
      expect(flash[:alert]).to eq("The certification was not deleted. Refused for the spec")
    end

    it "says the certification is in use when a project session points at it" do
      create(:proficient_project_session, level: "Beginner", certification: certification)
      delete admin_certification_path(certification), params: { locale: "fr" }
      expect(flash[:alert]).to eq(
        "La certification n'a pas été supprimée. D'autres éléments l'utilisent encore, il a donc été laissé tel quel."
      )
    end
  end

  describe "job order settings" do
    let(:blank_name) { "Name This field is required." }
    let(:job_type) { create(:job_type) }
    let(:service) { create(:job_service) }
    let(:option) { create(:job_option) }
    let(:group) { create(:job_service_group) }

    {
      "job type create" => [-> { post admin_job_types_path, params: { job_type: { name: "" } } },
                            "The job type was not created. "],
      "job type update" => [-> { patch admin_job_type_path(job_type), params: { job_type: { name: "" } } },
                            "The job type was not updated. "],
      "service create" => [-> { post admin_job_services_path, params: { job_service: { name: "" } } },
                           "The service was not created. "],
      "service update" => [-> { patch admin_job_service_path(service), params: { job_service: { name: "" } } },
                           "The service was not updated. "],
      "option create" => [-> { post admin_job_options_path, params: { job_option: { name: "" } } },
                          "The option was not created. "],
      "option update" => [-> { patch admin_job_option_path(option), params: { job_option: { name: "" } } },
                          "The option was not updated. "],
      "service group create" => [-> { post admin_job_service_groups_path, params: { job_service_group: { name: "" } } },
                                 "The service group was not created. "],
      "service group update" => [-> { patch admin_job_service_group_path(group), params: { job_service_group: { name: "" } } },
                                 "The service group was not updated. "]
    }.each do |name, (call, start)|
      it "names the failed #{name} and shows the validation message" do
        instance_exec(&call)
        expect(flash[:alert]).to start_with(start + blank_name)
      end
    end

    it "answers a failed update in French" do
      patch admin_job_type_path(job_type), params: { job_type: { name: "" }, locale: "fr" }
      expect(flash[:alert]).to start_with("Le type de travail n'a pas été modifié. ")
    end

    {
      "service" => [JobService, :service, "Le service n'a pas été supprimé."],
      "option" => [JobOption, :option, "L'option n'a pas été supprimée."],
      "service group" => [JobServiceGroup, :group, "Le groupe de services n'a pas été supprimé."]
    }.each do |name, (model, record, french)|
      it "names the failed #{name} delete in English and French" do
        target = send(record)
        refuse_writes(model, :destroy)
        delete send("admin_job_#{record == :group ? 'service_group' : "#{record}"}_path", target)
        expect(flash[:alert]).to match(/was not deleted\. Refused for the spec\z/)
      end

      it "answers a failed #{name} delete in French" do
        target = send(record)
        refuse_writes(model, :destroy)
        delete send("admin_job_#{record == :group ? 'service_group' : "#{record}"}_path", target), params: { locale: "fr" }
        expect(flash[:alert]).to eq("#{french} Refused for the spec")
      end
    end
  end

  describe "spaces" do
    let!(:space) { create(:space, name: "Alpha") }
    let!(:room) { create(:sub_space, space: space, name: "Room A") }

    it "names the failed create in English and French" do
      post admin_spaces_path, params: { space_params: { name: "" } }
      expect(flash[:alert]).to start_with("The space was not created. ")
      post admin_spaces_path, params: { space_params: { name: "" }, locale: "fr" }
      expect(flash[:alert]).to start_with("L'espace n'a pas été créé. ")
    end

    it "names the failed capacity and keycode updates and goes back to the page" do
      refuse_writes(Space, :update)
      post update_max_capacity_admin_spaces_path, params: { space_id: space.id, max_capacity: 9 }
      expect(flash[:alert]).to eq("The space capacity was not updated. Refused for the spec")
      patch update_keycode_admin_spaces_path, params: { space_id: space.id, keycode: "9999", locale: "fr" }
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("Le code d'accès de l'espace n'a pas été modifié. Refused for the spec")
    end

    it "names the sub space that was not renamed" do
      refuse_writes(SubSpace, :update)
      patch admin_space_update_sub_space_path(space_id: space.id, id: room.id), params: { name: "Room Z" }
      expect(flash[:alert]).to eq("The sub space was not renamed. Refused for the spec")
    end

    it "says why a space manager was not added, in French too" do
      patch add_space_manager_admin_spaces_path, params: { space_id: space.id, space_manager_id: create(:user, :staff).id }
      expect(flash[:alert]).to start_with("The space manager was not added. ")
      patch add_space_manager_admin_spaces_path,
            params: { space_id: space.id, space_manager_id: create(:user, :staff).id, locale: "fr" }
      expect(flash[:alert]).to start_with("Le responsable de l'espace n'a pas été ajouté. ")
    end

    it "says which limit values are missing" do
      patch admin_space_set_max_booking_duration_path(space_id: space.id, sub_space_id: room.id), params: { locale: "fr" }
      expect(flash[:alert]).to eq(
        "Choisissez un sous-espace et entrez le nombre d'heures de la limite à modifier."
      )
    end

    it "says the typed confirmation did not match" do
      delete admin_space_destroy_path(space_id: space.id), params: { id: space.id, admin_input: "alpha", locale: "fr" }
      expect(flash[:alert]).to eq("Le texte saisi ne correspond pas au nom de l'espace, rien n'a été supprimé.")
    end

    it "says the calendar URLs need a space" do
      put update_staff_needed_calendars_admin_spaces_path, params: { locale: "fr" }
      expect(flash[:alert]).to start_with("Les adresses des calendriers n'ont pas été enregistrées")
    end
  end

  describe "teams" do
    let!(:captain) { create(:user, :staff) }
    let!(:team) do
      Team.create!(name: "Alpha").tap { |t| TeamMembership.create!(team: t, user: captain, role: :captain) }
    end
    let(:member) { create(:user, :regular_user) }

    it "names the failed create and update, in French too" do
      post admin_teams_path, params: { team: { name: "" }, captain: captain.id }
      expect(flash[:alert]).to eq("The team was not created. Name A team name is required.")
      post admin_teams_path, params: { team: { name: "" }, captain: captain.id, locale: "fr" }
      expect(flash[:alert]).to start_with("L'équipe n'a pas été créée. ")
      patch admin_team_path(team), params: { team: { name: "" }, captain: captain.id, locale: "fr" }
      expect(flash[:alert]).to start_with("L'équipe n'a pas été modifiée. ")
    end

    it "names the member that could not be added and the role that is not known, in French too" do
      patch add_member_admin_team_path(team, member_id: member.id), params: { role: "captain", locale: "fr" }
      expect(flash[:alert]).to start_with("L'utilisateur n'a pas été ajouté à l'équipe. ")
      patch add_member_admin_team_path(team, member_id: member.id), params: { role: "boss", locale: "fr" }
      expect(flash[:alert]).to start_with("Choisissez un rôle")
    end

    it "says which members can be promoted or demoted, in French too" do
      TeamMembership.create!(team: team, user: member, role: :lead)
      patch promote_member_admin_team_path(team, member_id: member.id), params: { locale: "fr" }
      expect(flash[:alert]).to start_with("Le membre n'a pas été promu.")
      TeamMembership.find_by(user: member).update!(role: :regular_member)
      patch demote_member_admin_team_path(team, member_id: member.id), params: { locale: "fr" }
      expect(flash[:alert]).to start_with("Le membre n'a pas été rétrogradé.")
    end
  end

  describe "keys" do
    let!(:space) { create(:space) }
    let!(:key) { create(:key, :regular_key_type, :inventory_status, space: space, number: 11) }

    it "names the failed update and delete in English" do
      patch admin_key_path(key), params: { key: { number: "" } }
      expect(flash[:alert]).to start_with("The key was not updated. ")
      refuse_writes(Key, :destroy)
      delete admin_key_path(key)
      expect(flash[:alert]).to eq("The key was not deleted. Refused for the spec")
    end

    it "names the failed create and delete in French" do
      post admin_keys_path, params: { key: { number: 11, space_id: space.id, status: "inventory", key_type: "regular" }, locale: "fr" }
      expect(flash[:alert]).to start_with("La clé n'a pas été créée. ")
      refuse_writes(Key, :destroy)
      delete admin_key_path(key)
      expect(flash[:alert]).to eq("La clé n'a pas été supprimée. Refused for the spec")
    end

    it "names the key request that could not be approved or denied" do
      request = create(:key_request, :status_waiting_for_approval, :all_questions_answered, user: create(:user, :staff), supervisor: create(:user, :admin), space: space)
      refuse_writes(KeyRequest, :update)
      patch approve_key_request_admin_keys_path, params: { id: request.id }
      expect(flash[:alert]).to eq("The key request was not approved. Refused for the spec")
      patch deny_key_request_admin_keys_path, params: { id: request.id, locale: "fr" }
      expect(flash[:alert]).to eq("La demande de clé n'a pas été refusée. Refused for the spec")
    end

    it "says the request is no longer waiting, in French too" do
      request = create(:key_request, :status_waiting_for_approval, :all_questions_answered, user: create(:user, :staff), supervisor: create(:user, :admin), space: space)
      request.update_columns(status: KeyRequest.statuses[:approved])
      patch approve_key_request_admin_keys_path, params: { id: request.id, locale: "fr" }
      expect(flash[:alert]).to eq("Cette demande de clé n'attend plus d'approbation, elle a donc été laissée telle quelle.")
    end

    it "says which assignment was refused, in French" do
      holder = create(:user, :staff)
      create(:key_request, :status_approved, :all_questions_answered, user: holder, supervisor: create(:user, :admin), space: space)
      patch admin_key_assign_key_path(key), params: { key: { user_id: holder.id }, locale: "fr" }
      expect(flash[:alert]).to start_with("La clé n'a pas été attribuée.")
    end

    it "labels staff whose request form awaits approval on the assign page" do
      create(:key_request, :status_waiting_for_approval, :all_questions_answered,
             user: create(:user, :staff, name: "Waiting Holder"), supervisor: create(:user, :admin), space: space)
      get admin_key_assign_path(key)
      expect(response.body).to include("Waiting Holder")
      expect(response.body).to include("Request form awaiting approval")
    end

    it "refuses a holder without any key request" do
      patch admin_key_assign_key_path(key), params: { key: { user_id: create(:user, :staff).id } }
      expect(flash[:alert]).to eq("The key holder must have an approved key request.")
    end

    it "says which revoke was refused, in French" do
      patch admin_key_revoke_key_path(key), params: { locale: "fr" }
      expect(flash[:alert]).to start_with("La clé n'a pas été retirée.")
    end
  end

  describe "key transactions" do
    let!(:transaction_record) do
      create(:key, :regular_key_type, :inventory_status, space: create(:space), number: 5)
      KeyTransaction.create!(key: Key.last, user: create(:user, :staff), deposit_amount: 20)
    end

    it "asks for the return date, in French too" do
      patch admin_key_transaction_path(transaction_record), params: { key_transaction: { deposit_return_date: "" }, locale: "fr" }
      expect(flash[:alert]).to eq("Entrez la date de remboursement du dépôt.")
    end

    it "names the deposit that was not updated" do
      refuse_writes(KeyTransaction, :update)
      patch admin_key_transaction_path(transaction_record), params: { key_transaction: { deposit_return_date: "2024-02-02" } }
      expect(flash[:alert]).to eq("The deposit was not updated. Refused for the spec")
    end
  end

  describe "pi readers" do
    let!(:reader) { create(:pi_reader) }

    it "names the reader that was not updated and goes back to the page" do
      refuse_writes(PiReader, :update)
      patch admin_pi_reader_path(reader), params: { pi_reader_params: { pi_location: "Bench" }, locale: "fr" }
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("Le lecteur n'a pas été modifié. Refused for the spec")
    end

    it "says the space is gone when the update points at a missing space, in French too" do
      patch admin_pi_reader_path(reader), params: { pi_reader_params: { space_id: 0 } }
      expect(flash[:alert]).to eq("The reader was not updated. A record it refers to no longer exists. Reload the page and try again.")
      expect(response).to redirect_to(root_path)
      patch admin_pi_reader_path(reader), params: { pi_reader_params: { space_id: 0 }, locale: "fr" }
      expect(flash[:alert]).to start_with("Le lecteur n'a pas été modifié. Un élément auquel il fait référence")
    end

    it "names the reader that was not registered" do
      post admin_pi_readers_path, params: { pi_reader_params: { pi_mac_address: "", pi_location: "Door" } }
      expect(flash[:alert]).to start_with("The reader was not registered. ")
    end
  end

  describe "settings" do
    let!(:course) { create(:course_name) }

    it "names the failed course add, rename and remove" do
      post add_course_admin_settings_path, params: { name: "" }
      expect(flash[:alert]).to start_with("The course was not added. ")
      patch rename_course_admin_settings_path, params: { id: course.id, name: "", locale: "fr" }
      expect(flash[:alert]).to start_with("Le cours n'a pas été renommé. ")
      refuse_writes(CourseName, :destroy)
      delete remove_course_admin_settings_path, params: { id: course.id, locale: "en" }
      expect(flash[:alert]).to eq("The course was not removed. Refused for the spec")
    end

    it "names the failed message update and asks for a message, in French" do
      JobOrderMessage.create!(name: "processed", message: "Done")
      patch update_job_order_processed_admin_settings_path, params: { job_order_message: { message: "" }, locale: "fr" }
      expect(flash[:alert]).to start_with("Le message n'a pas été modifié. ")
      patch update_job_order_processed_admin_settings_path, params: { locale: "fr" }
      expect(flash[:alert]).to eq("Veuillez entrer un message.")
    end

    it "names the project whose featured status could not change" do
      repository = create(:repository)
      refuse_writes(Repository, :update)
      patch pin_unpin_repository_admin_settings_path, params: { repository_id: repository.id }
      expect(flash[:alert]).to eq("The featured status of the project was not changed. Refused for the spec")
    end
  end
end
