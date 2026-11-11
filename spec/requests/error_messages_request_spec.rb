# frozen_string_literal: true

require "rails_helper"

# The site controllers outside the admin screens answer a refused write with a sentence that names
# what was not saved followed by the record's validation messages, in the visitor's language. Mail
# that cannot be queued after a record is saved is reported and said so, never an error page.
RSpec.describe "Error messages", type: :request do
  include ContentSpecHelpers
  include ActiveJob::TestHelper

  let(:fr) { { locale: "fr" } }

  # Makes the next write on the model's records fail with a validation message.
  def refuse_writes(model, *methods)
    methods.each do |name|
      allow_any_instance_of(model).to receive(name) do |record|
        record.errors.add(:base, "Refused for the spec")
        false
      end
    end
  end

  describe "training screens" do
    it "names the failed exam delete in English and French" do
      content_sign_in_as(:admin)
      exam = create(:exam)
      refuse_writes(Exam, :destroy)
      delete exam_path(exam)
      expect(flash[:alert]).to eq("The exam was not deleted. Refused for the spec")
      delete exam_path(exam), params: fr
      expect(flash[:alert]).to eq("L'examen n'a pas été supprimé. Refused for the spec")
    end

    it "names the failed question update and delete" do
      content_sign_in_as(:admin)
      question = create(:question)
      refuse_writes(Question, :update, :destroy)
      patch question_path(question), params: { question: { description: "x" } }
      expect(flash[:alert]).to eq("The question was not updated. Refused for the spec")
      delete question_path(question), params: fr
      expect(flash[:alert]).to eq("La question n'a pas été supprimée. Refused for the spec")
    end

    it "names a duplicate required project in French" do
      content_sign_in_as(:admin)
      project = create(:proficient_project)
      required = create(:proficient_project)
      2.times { post project_requirements_path, params: { id: project.id, required_project_id: required.id }.merge(fr) }
      expect(flash[:alert]).to start_with("Le projet requis n'a pas été ajouté. ")
    end

    it "names a missing training in French" do
      content_sign_in_as(:admin)
      task = create(:volunteer_task)
      post require_trainings_path, params: { require_training: { volunteer_task_id: task.id, training_id: "" } }.merge(fr)
      expect(flash[:alert]).to start_with("La formation requise n'a pas été ajoutée à cette tâche de bénévolat. ")
    end
  end

  describe "announcements" do
    it "names the failed update and delete" do
      content_sign_in_as(:staff)
      announcement = create(:announcement, public_goal: "volunteer")
      refuse_writes(Announcement, :update, :destroy)
      patch announcement_path(announcement), params: { announcement: { description: "x" } }
      expect(flash[:alert]).to eq("The announcement was not updated. Refused for the spec")
      delete announcement_path(announcement), params: fr
      expect(flash[:alert]).to eq("L'annonce n'a pas été supprimée. Refused for the spec")
    end
  end

  describe "repository comments" do
    let(:owner) { create(:user, :regular_user) }
    let!(:repo) { create(:repository, owner: owner, title: "Talky", users: [owner]) }

    it "names a failed comment in French" do
      content_login!(owner)
      post comments_create_path(repo.id), params: { content: "" }.merge(fr)
      expect(flash[:alert]).to start_with("Le commentaire n'a pas été publié. ")
    end

    it "names a refused comment delete" do
      comment = create(:comment, repository: repo, user: owner, username: owner.username)
      content_login!(owner)
      refuse_writes(Comment, :destroy)
      delete comments_destroy_path(comment.id)
      expect(flash[:alert]).to eq("The comment was not deleted. Refused for the spec")
    end

    it "names a failed make in French" do
      content_login!(owner)
      post makes_create_path(owner.username, repo.id), params: { repository: { title: "", description: "x", photos_attributes: { "0" => { image: content_png_upload } } } }.merge(fr)
      expect(flash[:alert]).to start_with("La réalisation n'a pas été enregistrée. ")
    end
  end

  describe "repositories" do
    let(:owner) { create(:user, :regular_user) }
    let(:newbie) { create(:user, :regular_user) }
    let!(:repo) { create(:repository, owner: owner, title: "Talky", users: [owner]) }

    before { content_login!(owner) }

    it "names the failed member add" do
      refuse_writes(Repository, :save)
      patch add_member_repositories_path(owner.username),
            params: { repo_owner: { repository_id: repo.id, owner_username: newbie.username } }
      expect(flash[:alert]).to eq("The user was not added to the repository. Refused for the spec")
    end

    it "names the failed proposal link" do
      proposal = create(:project_proposal, approved: 1)
      refuse_writes(Repository, :save)
      patch link_to_pp_repositories_path(owner.username), params: { repo: { repository_id: repo.id, project_proposal_id: proposal.id } }
      expect(flash[:alert]).to eq("The project was not linked to the project proposal. Refused for the spec")
    end

    it "names the failed ownership transfer in French" do
      repo.users << newbie
      refuse_writes(Repository, :update)
      patch transfer_owner_repositories_path(owner.username),
            params: { repo_owner: { repository_id: repo.id, owner_id: newbie.id } }.merge(fr)
      expect(flash[:alert]).to eq("La propriété du dépôt n'a pas été transférée. Refused for the spec")
    end

    it "names an invalid update in French and starts the recently viewed list again from a broken cookie" do
      patch repository_path(owner.username, repo.slug), params: { repository: { title: "" } }.merge(fr)
      expect(flash[:alert]).to start_with("Le projet n'a pas été modifié. ")
      cookies[:recently_viewed] = "not json"
      get repository_path(owner.username, repo.slug)
      expect(JSON.parse(cookies[:recently_viewed].to_s.then { |v| CGI.unescape(v) }).values).to include("Talky")
      cookies[:recently_viewed] = CGI.escape("[1,2]")
      get repository_path(owner.username, repo.slug)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "project proposals" do
    let(:user) { create(:user, :regular_user) }
    let!(:approved) { create(:project_proposal, approved: 1) }

    before { content_login!(user) }

    it "names a failed proposal in French" do
      post project_proposals_path, params: { project_proposal: { title: "" } }.merge(fr)
      expect(flash[:alert]).to start_with("La proposition de projet n'a pas été créée. ")
    end

    it "names a failed update" do
      mine = create(:project_proposal, user: user)
      refuse_writes(ProjectProposal, :update)
      patch project_proposal_path(mine), params: { project_proposal: { title: "x" } }
      expect(flash[:alert]).to eq("The project proposal was not updated. Refused for the spec")
    end

    it "names a failed revision" do
      mine = create(:project_proposal, user: user)
      refuse_writes(ProjectProposal, :save)
      post create_revision_project_proposals_path, params: { old_project_proposal_id: mine.id }
      expect(flash[:alert]).to eq("The revision was not created. Refused for the spec")
    end

    it "names a repeated join in French" do
      2.times { post join_project_proposal_project_proposals_path, params: { project_proposal_id: approved.id }.merge(fr) }
      expect(flash[:alert]).to eq("Vous participez déjà à ce projet.")
    end
  end

  describe "help" do
    let(:form) { { help: { name: "John", email: "john@example.com", subject: "A long enough subject", comments: "Please help" } } }

    before { allow_any_instance_of(GithubIssuesService).to receive(:create_issue).and_return({ number: 42 }) }

    it "names a refused form in English and French" do
      post help_path, params: { help: { name: "J", email: "bad", subject: "short", comments: "" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(flash[:alert]).to start_with("Your issue was not submitted. ")
      post help_path, params: { help: { name: "J", email: "bad", subject: "short", comments: "" } }.merge(fr)
      expect(flash[:alert]).to start_with("Votre demande n'a pas été soumise. ")
    end

    it "keeps a saved report whose copy cannot be queued, says so and reports it" do
      allow(MsrMailer).to receive(:issue_email_to_team).and_raise(ActiveJob::EnqueueError, "queue down")
      expect(Rails.error).to receive(:report).with(an_instance_of(ActiveJob::EnqueueError), hash_including(handled: true))
      post help_path, params: form
      expect(response).to redirect_to(help_path)
      expect(flash[:alert]).to eq(I18n.t("errors.help.copy_not_sent"))
    end

    it "reports an unexpected error and shows the form again with the reference" do
      allow_any_instance_of(Help).to receive(:save).and_raise(RuntimeError, "boom")
      expect(Rails.error).to receive(:report).with(an_instance_of(RuntimeError), hash_including(handled: true))
      post help_path, params: form
      expect(response).to have_http_status(:unprocessable_content)
      expect(flash[:alert]).to match(/quote reference \h{8}\./)
      expect(flash[:alert]).not_to include("boom")
    end
  end

  describe "printers" do
    let(:printer) { create(:printer, :UM3_01) }

    before { content_sign_in_as(:staff) }

    def link(user_id, printer_id: printer.id, **extra)
      patch link_printer_to_user_printers_path(format: :json), params: { printer: { printer_id: printer_id, user_id: user_id } }.merge(extra)
    end

    it "names the missing printer and the missing user in English and French" do
      link(create(:user, :regular_user).id, printer_id: 0)
      expect(JSON.parse(response.body)).to eq([["alert", "That printer no longer exists. Reload the page and choose a printer again."]])
      link(0, **fr)
      expect(JSON.parse(response.body)).to eq([["alert", "Cet utilisateur n'existe plus. Choisissez de nouveau un utilisateur."]])
    end

    it "names a session that could not be saved" do
      refuse_writes(PrinterSession, :save)
      link(create(:user, :regular_user).id)
      expect(JSON.parse(response.body)).to eq([["alert", "The printer was not linked to the user. Refused for the spec"]])
    end

    describe "issues" do
      let(:issue) { create(:printer_issue, printer: printer, reporter: create(:user, :staff)) }

      it "names a failed create in French" do
        post printer_issues_path, params: { printer_issue: { printer_id: printer.id, summary: "" } }.merge(fr)
        expect(flash[:alert]).to start_with("Le problème d'imprimante n'a pas été créé. ")
      end

      it "names a failed delete" do
        content_sign_in_as(:admin)
        refuse_writes(PrinterIssue, :destroy)
        delete printer_issue_path(issue)
        expect(flash[:alert]).to eq("The printer issue was not deleted. Refused for the spec")
      end

      it "keeps the new issue when the notification cannot be queued, says so and reports it" do
        Setting.maintenance_email = "maint@example.com"
        allow(MsrMailer).to receive(:new_printer_issue).and_raise(ActiveJob::EnqueueError, "queue down")
        expect(Rails.error).to receive(:report).with(an_instance_of(ActiveJob::EnqueueError), hash_including(handled: true))
        expect { post printer_issues_path, params: { printer_issue: { printer_id: printer.id, summary: "Bed issue: warped", description: "x" } } }
          .to change(PrinterIssue, :count).by(1)
        expect(flash[:alert]).to eq(I18n.t("errors.printers.notification_not_sent"))
      end
    end
  end

  describe "learning area" do
    let(:learning_module) { create(:learning_module, training: create(:training)) }
    let(:user) { create(:user, :regular_user) }

    it "names a failed create in French" do
      content_sign_in_as(:admin)
      post learning_area_index_path, params: { learning_module: { title: "", training_id: create(:training).id, level: "Beginner" } }.merge(fr)
      expect(flash[:alert]).to start_with("Le module d'apprentissage n'a pas été créé. ")
    end

    it "says to start a module before completing it, in French" do
      content_login!(user)
      post completed_learning_module_track_index_path(learning_module_id: learning_module.id), params: fr
      expect(flash[:alert]).to eq("Commencez le module d'apprentissage avant de le marquer comme terminé.")
    end

    it "names a failed completion" do
      content_login!(user)
      LearningModuleTrack.create!(user: user, learning_module: learning_module)
      refuse_writes(LearningModuleTrack, :update)
      post completed_learning_module_track_index_path(learning_module_id: learning_module.id)
      expect(flash[:alert]).to eq("The learning module was not marked as completed. Refused for the spec")
    end

    it "reports a database error starting a module and quotes the reference" do
      content_login!(user)
      allow(LearningModuleTrack).to receive(:for_user_and_module!).and_raise(ActiveRecord::StatementInvalid, "boom")
      expect(Rails.error).to receive(:report).with(an_instance_of(ActiveRecord::StatementInvalid), hash_including(handled: true))
      post start_learning_module_track_index_path(learning_module_id: learning_module.id)
      expect(flash[:alert]).to match(/\AThe learning module was not started\. .*quote reference \h{8}\./)
    end

    it "names a refused start" do
      content_login!(user)
      record = LearningModuleTrack.new
      record.errors.add(:base, "Refused for the spec")
      allow(LearningModuleTrack).to receive(:for_user_and_module!).and_raise(ActiveRecord::RecordInvalid.new(record))
      post start_learning_module_track_index_path(learning_module_id: learning_module.id)
      expect(flash[:alert]).to eq("The learning module was not started. Refused for the spec")
    end
  end

  describe "development program, kits, videos and key requests" do
    it "names a refused join in French" do
      content_sign_in_as(:regular)
      refuse_writes(Program, :save)
      post join_development_program_development_programs_path, params: fr
      expect(flash[:alert]).to eq("Vous n'avez pas rejoint le programme de développement. Refused for the spec")
    end

    it "tells a member who already joined the Development Program so" do
      user = content_sign_in_as(:regular)
      Program.create!(user: user, program_type: Program::DEV_PROGRAM)
      post join_development_program_development_programs_path
      expect(flash[:alert]).to eq("You already joined the Program. You can already access it!")
    end

    it "names a failed kit create in French and a refused kit delete" do
      content_sign_in_as(:admin)
      post project_kits_path, params: { project_kit: { user_id: create(:user, :regular_user).id, proficient_project_id: "" } }.merge(fr)
      expect(flash[:alert]).to start_with("La trousse n'a pas été créée. ")
      kit = create(:project_kit)
      refuse_writes(ProjectKit, :destroy)
      delete project_kit_path(kit), params: { locale: "en" }
      expect(flash[:alert]).to eq("The kit was not deleted. Refused for the spec")
    end

    it "names a refused video upload in French" do
      content_sign_in_as(:admin)
      refuse_writes(Video, :save)
      post videos_path, params: { video: { proficient_project_id: create(:proficient_project).id } }.merge(fr)
      expect(flash[:alert]).to eq("La vidéo n'a pas été téléversée. Refused for the spec")
    end

    it "names a failed key request in French and an already submitted request" do
      staff = content_sign_in_as(:staff)
      post key_requests_path, params: { key_request: { phone_number: "abc" } }.merge(fr)
      expect(flash[:alert]).to start_with("La demande de clé n'a pas été commencée. ")
      request = create(:key_request, :status_in_progress, user: staff, supervisor: create(:user, :staff), space: create(:space))
      allow_any_instance_of(KeyRequest).to receive(:submit).and_return(false)
      patch key_request_steps_path(key_request_id: request.id, step: 6), params: { locale: "en" }
      expect(flash[:alert]).to eq("This key request was already submitted, so it cannot be submitted again.")
    end
  end

  describe "users and memberships" do
    it "refuses a regular user changing programs, in French" do
      content_sign_in_as(:regular)
      post change_programs_users_path, params: { user_id: create(:user, :regular_user).id }.merge(fr)
      expect(flash[:alert]).to eq("Vous ne pouvez pas accéder à cette zone.")
    end

    it "names an unknown membership tier in French" do
      content_sign_in_as(:regular)
      post memberships_path, params: { membership: { membership_tier_id: 999_999 } }.merge(fr)
      expect(flash[:alert]).to start_with("L'adhésion n'a pas été créée. ")
    end
  end
end
