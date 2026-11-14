# frozen_string_literal: true

require "rails_helper"

# The exam, proficient project, help, print, volunteer task and account maintenance mails are delivered in the
# language their recipient saved: subject, body, sign-off and footer.
RSpec.describe "Member mails in the recipient's language", type: :mailer do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:english) { create(:user, :regular_user, name: "ada lovelace", locale: "en") }
  let(:french) { create(:user, :regular_user, name: "ada lovelace", locale: "fr") }
  let(:staff) { create(:user, :staff, name: "Grace Hopper", locale: "en") }
  let(:session) { create(:training_session, user: staff, created_at: Time.zone.local(2026, 3, 4, 10)) }
  let(:skill) { create(:skill, name: "Technical") }
  let(:project) { create(:proficient_project, title: "Mail project", training: create(:training, skill: skill)) }
  let(:task) { create(:volunteer_task, title: "booth duty") }

  before { ActionMailer::Base.deliveries.clear }

  def deliver(&build_mail)
    build_mail.call.deliver_later
    perform_enqueued_jobs
    ActionMailer::Base.deliveries.last
  end

  def text(mail) = CGI.unescapeHTML(mail.body.decoded)

  def exam(user, status) = create(:exam, user: user, training_session: session, status: status, score: 83)

  def order_item(user) = create(:order_item, order: create(:order, :completed, user_id: user.id), proficient_project: project,
                                             admin_comments: "")

  def mails_for(user)
    {
      finishing_exam: -> { MsrMailer.finishing_exam(user, exam(user, "passed")) },
      send_exam: -> { MsrMailer.send_exam(user, session) },
      issue_email: -> { MsrMailer.issue_email("Ada", user.email, "Broken page", "It is broken", true, "1.2.3", account: user) },
      print_failed: -> { MsrMailer.print_failed(create(:printer, :UM2P_01), user, "nozzle") },
      send_kit_email: -> { MsrMailer.send_kit_email(user, project.id) },
      send_results_pp: -> { MsrMailer.send_results_pp(order_item(user), user, "Passed") },
      send_user_pp_evaluation: -> { MsrMailer.send_user_pp_evaluation(project, user) },
      volunteer_joining: -> { MsrMailer.send_notification_to_volunteer_for_joining_task(task.id, user.id, staff.id) },
      task_request: -> { MsrMailer.send_notification_for_task_request(task.id, user.id) },
      task_request_update: lambda {
        MsrMailer.send_notification_for_task_request_update(create(:volunteer_task_request, user: user, volunteer_task: task).id)
      },
      renamed_user: -> { TaskMailer.with(email: user.email, previous_username: "old_ada", new_username: "ada").renamed_user },
      merged_user: -> { TaskMailer.with(email: user.email, username: "ada").merged_user }
    }
  end

  english_texts = {
    finishing_exam: ["You finished your exam", "Your score was 83. You passed the exam.", "Congratulations."],
    send_exam: ["An exam was sent to you", "Sign in to your account:", "You have 3 days to complete the exam.", "Start exam"],
    issue_email: ["Issue Report | Broken page", "We have received the following help request from you:",
                  "Subject: <b>Broken page</b>", "App Version: 1.2.3"],
    print_failed: ["Your 3D print on 01 has failed", "you started a print job at the MakerSpace", "CEED Team"],
    send_kit_email: ["Your proficient project kit order", "We received your kit order for your Mail project project.",
                     "opening hours"],
    send_results_pp: ["Your Proficient Project Results", "your proficient project has <b>passed</b>", "Admin Comments:",
                      "See my progress"],
    send_user_pp_evaluation: ["Your Proficient Project Request", "The proficient project (Mail project) has been submitted",
                              "This project has no drop-off locations."],
    volunteer_joining: ["New join in task: Booth duty", "You just joined the task <b>Booth duty</b>.", "Check it <a"],
    task_request: ["New Request for task: Booth duty", "A new request was made for the Task <b>Booth duty</b>."],
    task_request_update: ["Your request was updated: Booth duty", "a volunteer task you're interested in was updated"],
    renamed_user: ["Makerepo | Your account username was renamed", "Your username was changed from <b>old_ada</b> to <b>ada</b>."],
    merged_user: ["Makerepo | Duplicate accounts merged", "We have merged all your accounts", "forgot password form"]
  }.freeze

  french_texts = {
    finishing_exam: ["Vous avez terminé votre examen", "Votre note est de 83. Vous avez réussi l'examen.", "Félicitations!"],
    send_exam: ["Un examen vous a été envoyé", "Connectez-vous à votre compte :", "Vous avez 3 jours pour faire l'examen.",
                "Commencer l'examen"],
    issue_email: ["Signalement de problème | Broken page", "Nous avons reçu la demande d'aide suivante de votre part :",
                  "Objet : <b>Broken page</b>", "Version de l'application : 1.2.3"],
    print_failed: ["Votre impression 3D sur l'imprimante 01 a échoué", "vous avez lancé une impression au Makerspace",
                   "L'équipe du CGEC"],
    send_kit_email: ["Votre commande de trousse de projet de compétence", "Nous avons reçu votre commande de trousse pour votre projet Mail project.",
                     "heures d'ouverture"],
    send_results_pp: ["Résultats de votre projet de compétence", "votre projet de compétence a été <b>réussi</b>",
                      "Commentaires de l'administration :", "Voir ma progression"],
    send_user_pp_evaluation: ["Votre demande de projet de compétence", "Le projet de compétence (Mail project) a bien été soumis.",
                              "Ce projet n'a aucun lieu de remise."],
    volunteer_joining: ["Nouvelle inscription à la tâche : Booth duty", "Vous venez de rejoindre la tâche <b>Booth duty</b>.",
                        "Consultez-la <a"],
    task_request: ["Nouvelle demande pour la tâche : Booth duty", "Une nouvelle demande a été faite pour la tâche <b>Booth duty</b>."],
    task_request_update: ["Votre demande a été mise à jour : Booth duty", "une tâche de bénévolat qui vous intéresse a été mise à jour"],
    renamed_user: ["MakerRepo | Votre nom d'utilisateur a été changé", "Votre nom d'utilisateur <b>old_ada</b> a été remplacé par <b>ada</b>."],
    merged_user: ["MakerRepo | Comptes en double fusionnés", "Nous avons fusionné tous vos comptes",
                  "formulaire de mot de passe oublié"]
  }.freeze

  english_texts.each_key do |name|
    it "delivers #{name} in English to a user who saved English" do
      subject_line, *phrases = english_texts.fetch(name)
      mail = deliver(&mails_for(english).fetch(name))

      expect(mail.to).to eq([english.email])
      expect(mail.subject).to eq(subject_line)
      expect(text(mail)).to include(*phrases, "Thank you,")
      expect(text(mail)).not_to include("Bonjour", "Merci,", "Vous avez reçu")
    end

    it "delivers #{name} in French to a user who saved French" do
      subject_line, *phrases = french_texts.fetch(name)
      mail = deliver(&mails_for(french).fetch(name))

      expect(mail.to).to eq([french.email])
      expect(mail.subject).to eq(subject_line)
      expect(text(mail)).to include(*phrases, "Merci,", "Vous avez reçu ce courriel")
      expect(text(mail)).not_to include("Hello", "Thank you,", "You have received", "MakerRepo Team", "CEED Team")
    end
  end

  it "gives the failed exam wording and the retry line in each language" do
    expect(text(deliver { MsrMailer.finishing_exam(english, exam(english, "failed")) }))
      .to include("You failed the exam.", "If this is your first try", "Check <a href=\"http://makerepo.com/exams\">Exams</a> for new exams.")
    expect(text(deliver { MsrMailer.finishing_exam(french, exam(french, "failed")) }))
      .to include("Vous avez échoué à l'examen.", "S'il s'agit de votre première tentative", ">Examens</a>")
  end

  it "names the status of an exam that is not graded yet, in each language" do
    expect(text(deliver { MsrMailer.finishing_exam(english, exam(english, "incomplete")) }))
      .to include("Your score was 83. You incomplete the exam.")
    expect(text(deliver { MsrMailer.finishing_exam(french, exam(french, "incomplete")) }))
      .to include("Votre note est de 83. Statut de l'examen : incomplete.")
    expect(text(deliver { MsrMailer.exam_results_staff(english, exam(english, "not started")) }))
      .to include("Hence, He/she not started the exam.")
  end

  it "gives the failed proficient project wording in each language" do
    expect(text(deliver { MsrMailer.send_results_pp(order_item(english), english, "Failed") }))
      .to include("your proficient project has <b>failed</b>", "None")
    expect(text(deliver { MsrMailer.send_results_pp(order_item(french), french, "Failed") }))
      .to include("votre projet de compétence n'a <b>pas été réussi</b>", "Aucun")
  end

  it "names the drop-off location in each language" do
    project.update!(drop_off_location: create(:drop_off_location, name: "Front desk"))
    expect(text(deliver { MsrMailer.send_user_pp_evaluation(project, english) }))
      .to include("Please <b>drop off</b> your project <b>here</b>: Front desk")
    expect(text(deliver { MsrMailer.send_user_pp_evaluation(project, french) }))
      .to include("Veuillez <b>déposer</b> votre projet à cet <b>endroit</b> : Front desk")
  end

  describe "exam results to the session's staff" do
    it "is written in the staff member's language, not the trainee's, with the session date in that language" do
      mail = deliver { MsrMailer.exam_results_staff(french, exam(french, "failed")) }

      expect([mail.to, mail.subject]).to eq([[staff.email], "Ada finished an exam"])
      expect(text(mail)).to include("(Mar  4 2026)", "Hence, He/she failed the exam.", "If this is his/her first try",
                                    "No more actions are needed.")
    end

    it "is written in French to a staff member who saved French" do
      staff.update!(locale: "fr")
      mail = deliver { MsrMailer.exam_results_staff(english, exam(english, "passed")) }

      expect(mail.subject).to eq("Ada a terminé un examen")
      expect(text(mail)).to include("(4 mars 2026)", "Cette personne a donc réussi l'examen.", "Vous n'avez rien d'autre à faire.")
      expect(text(mail)).not_to include("S'il s'agit de sa première tentative")
    end
  end

  describe "volunteer task request mails" do
    def request_update(user) = MsrMailer.send_notification_for_task_request_update(
      create(:volunteer_task_request, user: user, volunteer_task: task).id
    )

    it "name the volunteer team's address to write to, in English" do
      expect(text(deliver { MsrMailer.send_notification_for_task_request(task.id, english.id) }))
        .to include("you can send an email to volunteer@makerepo.com.")
      expect(text(deliver { request_update(english) })).to include("you can send an email to volunteer@makerepo.com.")
    end

    it "name the volunteer team's address to write to, in French" do
      expect(text(deliver { MsrMailer.send_notification_for_task_request(task.id, french.id) }))
        .to include("vous pouvez écrire à volunteer@makerepo.com.")
      expect(text(deliver { request_update(french) })).to include("vous pouvez écrire à volunteer@makerepo.com.")
    end
  end

  describe "a user joining a task, to the task's staff" do
    it "is written in the staff member's language" do
      expect(deliver { MsrMailer.send_notification_to_staff_for_joining_task(task.id, french.id, staff.id) }.subject)
        .to eq("New join in task: Booth duty")
      staff.update!(locale: "fr")
      mail = deliver { MsrMailer.send_notification_to_staff_for_joining_task(task.id, english.id, staff.id) }

      expect(mail.subject).to eq("Nouvelle inscription à la tâche : Booth duty")
      expect(text(mail)).to include("<b>Ada lovelace</b> a rejoint la tâche <b>Booth duty</b>.")
    end

    it "is written in English to the volunteer team's address, which has no account" do
      mail = deliver { MsrMailer.send_notification_to_staff_for_joining_task(task.id, french.id, nil) }

      expect([mail.to, mail.subject]).to eq([["volunteer@makerepo.com"], "New join in task: Booth duty"])
      expect(text(mail)).to include("The user <b>Ada lovelace</b> joined the task <b>Booth duty</b>.")
    end
  end

  it "keeps the recipients of the help and print mails in each language" do
    issue = deliver { MsrMailer.issue_email("Ada", french.email, "Help", "Text", nil) }
    expect([issue.to, issue.bcc]).to eq([[french.email], ["uottawa.makerepo@gmail.com"]])
    printed = deliver { MsrMailer.print_failed(create(:printer, :UM2P_01), french, "nozzle") }
    expect([printed.to, printed.bcc, printed.reply_to]).to eq([[french.email], ["uottawa.makerepo@gmail.com"], ["makerspace@uottawa.ca"]])
  end
end
