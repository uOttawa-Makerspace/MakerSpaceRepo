# frozen_string_literal: true

require "rails_helper"

# The exam pages and the admin question bank read their wording from config/locales/exams.yml:
# the same page under ?locale=fr is in French, while questions and answers are shown as the
# admin wrote them. Text is compared with whitespace collapsed, as a browser shows it.
RSpec.describe "Exam pages in French", type: :request do
  include ActiveJob::TestHelper

  around { |example| travel_to(Time.zone.local(2026, 3, 4, 15, 7, 0)) { example.run } }

  let(:fixture) { build_exam_fixture }
  let(:student) { fixture[:user] }

  def exam_for(status, **attrs)
    create(:exam, user: student, training_session: fixture[:session], status: status,
                  category: fixture[:training].name_en, **attrs).tap do |exam|
      fixture[:questions].each { |q| ExamQuestion.create!(exam: exam, question: q[:question]) }
    end
  end

  def page_text
    Nokogiri::HTML(response.body).at_css("body").text.gsub(/[[:space:]]+/, " ")
  end

  def visit(path, locale, params = {})
    get path, params: params.merge(locale: locale)
    expect(response).to have_http_status(:ok)
    page_text
  end

  def answer_all(exam, correct:)
    fixture[:questions].each do |q|
      answer = correct ? q[:correct] : q[:wrongs].first
      post exam_responses_path(format: :js), params: { exam_id: exam.id, answer_id: answer.id }
    end
  end

  describe "exam list" do
    before do
      exam_for(Exam::STATUS[:not_started])
      exam_for(Exam::STATUS[:passed], score: 80)
      exam_for(Exam::STATUS[:incomplete], expired_at: 1.hour.ago)
      log_in!(student)
    end

    it "is in French, with French dates" do
      text = visit(exams_path, "fr")

      expect(text).to include("Examens", "Date de création", "Expire le", "Catégorie", "Statut", "Note",
                              "Non commencé", "Réussi", "Expiré", "Commencer l'examen", "S. O.", "4 mars 2026", "15 h 07")
      expect(text).not_to include("Date Created", "Start Exam", "Not started", "Passed", "Mar 4, 2026")
    end

    it "keeps the English wording" do
      text = visit(exams_path, "en")

      expect(text).to include("Exams", "Date Created", "Expires at", "Not started", "Passed", "Expired",
                              "Start Exam", "NA", "Mar 4, 2026", "03:07 pm")
    end

    it "says there are no exams in French" do
      log_in!(create(:user, :regular_user))

      expect(visit(exams_path, "fr")).to include("Vous n'avez aucun examen.")
    end
  end

  describe "exam page" do
    let(:exam) { exam_for(Exam::STATUS[:incomplete]) }

    before { log_in!(student) }

    it "numbers the questions and offers to finish in French, with the question text as written" do
      text = visit(exam_path(exam), "fr")

      expect(text).to include("Question 1", fixture[:questions].first[:correct].description.to_plain_text)
      expect(response.body).to include(%(type="submit">Terminer l&#39;examen</button>))
    end

    it "shows the score in French after finishing" do
      answer_all(exam, correct: true)
      perform_enqueued_jobs { post finish_exam_exams_path(exam_id: exam.id, locale: "fr") }

      expect(flash[:notice]).to eq("Note : 100. Vous avez réussi l'examen.")
    end

    it "shows a failed score in French" do
      answer_all(exam, correct: false)
      perform_enqueued_jobs { post finish_exam_exams_path(exam_id: exam.id, locale: "fr") }

      expect(flash[:notice]).to eq("Note : 0. Vous avez échoué à l'examen.")
    end

    it "keeps the English score message" do
      answer_all(exam, correct: true)
      perform_enqueued_jobs { post finish_exam_exams_path(exam_id: exam.id) }

      expect(flash[:notice]).to eq("Score: 100. You passed the exam.")
    end

    it "refuses a finished exam in French" do
      exam.update!(status: Exam::STATUS[:passed], score: 100)

      get exam_path(exam, locale: "fr")
      expect(flash[:alert]).to eq("Vous ne pouvez pas accéder à un examen une fois qu'il est terminé.")

      post finish_exam_exams_path(exam_id: exam.id, locale: "fr")
      expect(flash[:alert]).to eq("Vous ne pouvez pas terminer un examen déjà terminé.")
    end

    it "refuses an expired exam in French" do
      exam.update!(expired_at: 1.minute.ago)

      get exam_path(exam, locale: "fr")
      expect(flash[:alert]).to eq("Cet examen est expiré.")
    end

    it "refuses an exam with no questions in French" do
      empty = create(:exam, user: student, training_session: fixture[:session], status: Exam::STATUS[:incomplete])

      post finish_exam_exams_path(exam_id: empty.id, locale: "fr")
      expect(flash[:alert]).to eq("Cet examen ne contient aucune question. Demandez au personnel de vous le renvoyer.")
    end

    it "refuses another user's exam in French" do
      log_in!(create(:user, :regular_user))

      get exam_path(exam, locale: "fr")
      expect(flash[:alert]).to eq("Vous ne pouvez pas accéder à cette section.")

      post exam_responses_path(format: :js, locale: "fr"), params: { exam_id: exam.id, answer_id: fixture[:questions].first[:correct].id }
      expect(flash[:alert]).to eq("Action non permise")
    end
  end

  describe "admin" do
    let(:space) { create(:space) }
    let(:admin) { create(:user, :admin, space: space) }
    let(:question) { fixture[:questions].first[:question] }

    # The list holds one question: the index loads trainings and authors per row.
    let!(:listed) do
      create(:question, level: "Beginner", trainings: [create(:training, spaces: [space])]).tap do |q|
        Answer.create!(question: q, correct: true, description: "right")
      end
    end

    before { log_in!(admin) }

    it "deletes an exam with a French message" do
      exam = exam_for(Exam::STATUS[:incomplete])

      delete exam_path(exam, locale: "fr")
      expect(flash[:notice]).to eq("Examen supprimé")
    end

    it "lists the questions in French" do
      text = visit(questions_path, "fr")

      expect(text).to include("Questions pour", "Nouvelle question", "Date de soumission", "Niveau", "Créée par",
                              "Débutant", "Modifier", "Voir", "Supprimer", "(mars)")
      expect(response.body).to include('placeholder="Rechercher par : catégorie, description, ..."')
      expect(text).to match(%r{Affichage de \d+ à \d+ sur \d+ questions})
    end

    it "keeps the English question list" do
      text = visit(questions_path, "en")

      expect(text).to include("Questions for", "New Question", "Date Submitted", "Level", "Created by", "Beginner", "(Mar)")
      expect(text).to match(/Displaying \d+ - \d+ of \d+ questions/)
    end

    it "says there are no questions in French" do
      admin.update!(space: create(:space))

      expect(visit(questions_path, "fr")).to include("Aucune question n'a encore été créée.")
    end

    it "shows the new-question form in French, keeping the stored level values" do
      text = visit(new_question_path, "fr")

      expect(text).to include("Nouvelle question", "Catégories :", "La réponse 1 sera la bonne réponse", "Niveau")
      expect(response.body).to include('<option value="Beginner">Débutant</option>',
                                       'placeholder="Réponse 1 : écrivez la description de la réponse ici..."',
                                       'title="4 réponses"', 'value="Créer la question"')
    end

    it "keeps the English new-question form" do
      visit(new_question_path, "en")

      expect(response.body).to include('<option value="Beginner">Beginner</option>',
                                       'placeholder="Answer 1: Write the answer description here..."', 'value="Create question"')
    end

    it "shows the edit form and a question in French" do
      text = visit(edit_question_path(question), "fr")
      expect(text).to include("Modifier la question", "La première réponse est la bonne réponse.", "Retirer", "Ajouter une réponse")
      expect(response.body).to include('<option selected="selected" value="Beginner">Débutant</option>', 'value="Modifier la question"')

      text = visit(question_path(question), "fr")
      expect(text).to include(%(Question dans « #{fixture[:training].name} »), question.description)
    end

    it "shows the question bank messages in French" do
      get edit_question_path(question, n_answers: 6, locale: "fr")
      expect(flash[:notice]).to eq("Réponse ajoutée. Veuillez en rédiger le contenu!")

      post questions_path(locale: "fr"), params: { question: { description: "Nouvelle?", level: "Beginner", training_ids: [fixture[:training].id.to_s],
                                                               answers_attributes: { "0" => { description: "a" }, "1" => { description: "b" } } } }
      expect(flash[:notice]).to eq("La nouvelle question a été créée!")

      patch question_path(question, locale: "fr"), params: { question: { description: "Changée" } }
      expect(flash[:notice]).to eq("La question a été modifiée")

      delete remove_answer_question_path(question, answer_id: fixture[:questions].first[:wrongs].first.id, locale: "fr")
      expect(flash[:notice]).to eq("La réponse a été retirée")

      delete question_path(question, locale: "fr")
      expect(flash[:notice]).to eq("La question a été supprimée")
    end

    it "deletes a question image with a French message" do
      question.images.attach(io: File.open(Rails.root.join("spec/support/assets/test.png")), filename: "test.png", content_type: "image/png")

      delete delete_individually_questions_path(locale: "fr"), params: { id: question.images.attachments.first.id, question_id: question.id }
      expect(flash[:notice]).to eq("L'image de la question a été supprimée")
    end
  end
end
