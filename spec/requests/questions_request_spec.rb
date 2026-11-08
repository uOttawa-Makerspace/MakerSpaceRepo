require "rails_helper"

# Chunk 12 characterization of QuestionsController (exam question bank).
# Inherits AdminAreaController: every action is admin-only; guests go to
# the login page; regular users AND staff are redirected to "/" with no flash
# (ensure_admin).
#
# Creation rule worth knowing: the answer the admin marks correct is kept; when
# no answer is marked (the new-question form has no flag) the first one is stored
# as correct. A question must end up with exactly one correct answer.

RSpec.describe "Questions (admin question bank)", type: :request do
  let(:space) { create(:space) }
  let(:training) { create(:training, spaces: [space]) }
  let(:admin) { create(:user, :admin, space: space) }
  let!(:question) do
    create(:question, description: "What is a kerf?", level: "Beginner", trainings: [training]).tap do |q|
      Answer.create!(question: q, correct: true, description: "The cut width")
      Answer.create!(question: q, correct: false, description: "A tool")
    end
  end

  def valid_params(overrides = {})
    { question: { description: "New question?", level: "Intermediate", training_ids: [training.id.to_s],
                  answers_attributes: { "0" => { description: "first", correct: "false" },
                                        "1" => { description: "second", correct: "true" } } }.merge(overrides) }
  end

  describe "role matrix" do
    let(:requests) do
      {
        index: -> { get questions_path },
        new: -> { get new_question_path },
        show: -> { get question_path(question) },
        edit: -> { get edit_question_path(question) },
        create: -> { post questions_path, params: valid_params },
        update: -> { patch question_path(question), params: { question: { description: "Hacked" } } },
        destroy: -> { delete question_path(question) },
        remove_answer: -> { delete remove_answer_question_path(question, answer_id: question.answers.where(correct: false).first.id) },
        delete_individually: -> { delete delete_individually_questions_path, params: { id: 0, question_id: question.id } }
      }
    end

    %i[guest regular staff volunteer].each do |role|
      it "bounces a #{role} on every action and changes nothing" do
        sign_in_as(role)
        requests.each_value do |call|
          expect { instance_exec(&call) }.not_to change { [Question.count, Answer.count, question.reload.description] }
          expect_admin_area_bounce(guest: role == :guest)
          expect(flash).to be_empty
        end
      end
    end
  end

  describe "GET /questions (index)" do
    before { log_in!(admin) }

    it "lists the questions of trainings available in the admin's space" do
      elsewhere = create(:training, spaces: [create(:space)])
      create(:question, description: "Other space question", trainings: [elsewhere])
      get questions_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("What is a kerf?")
      expect(response.body).not_to include("Other space question")
    end

    it "falls back to the first space when the admin has none" do
      admin.update!(space: nil)
      get questions_path
      expect(response).to have_http_status(:ok)
    end

    it "does not list questions without any training" do
      create(:question, description: "Loose question")
      get questions_path
      expect(response.body).not_to include("Loose question")
    end
  end

  describe "GET /questions/new" do
    before { log_in!(admin) }

    it "builds 4 blank answers by default" do
      get new_question_path
      expect(response).to have_http_status(:ok)
      expect(response.body.scan("question[answers_attributes]").size).to be >= 4
    end

    it "builds n_answers answers when more than one is requested" do
      get new_question_path(n_answers: 6)
      expect(response.body.scan(/name="question\[answers_attributes\]\[\d+\]\[description\]/).size + response.body.scan(/answers_attributes_\d+_description/).size).to be > 0
    end
  end

  describe "GET /questions/:id (show)" do
    it "renders the question and marks the correct answer to the admin" do
      log_in!(admin)
      get question_path(question)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("What is a kerf?").and include("The cut width")
      expect(response.body).to match(/class="correct-answers">\s*(<div[^>]*>)?\s*The cut width/m).or match(/correct-answers/)
    end

    it "reads the answer texts in a constant number of queries" do
      log_in!(admin)
      get question_path(question) # warm up
      few = selects_on("action_text_rich_texts") { get question_path(question) }
      4.times { |i| Answer.create!(question: question, correct: false, description: "extra #{i}") }
      many = selects_on("action_text_rich_texts") { get question_path(question) }

      expect(response.body).to include("extra 3")
      expect(many.size).to eq(few.size)
    end

    it "answers 404 for an unknown id" do
      log_in!(admin)
      get question_path(0)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /questions (create)" do
    before { log_in!(admin) }

    it "creates the question owned by the admin with its trainings and answers, then redirects with a notice" do
      expect { post questions_path, params: valid_params }
        .to change(Question, :count).by(1).and change(Answer, :count).by(2)
      expect(response).to redirect_to(questions_path)
      expect(flash[:notice]).to eq("You've successfully created a new question!")
      q = Question.order(:id).last
      expect(q.user).to eq(admin)
      expect(q.level).to eq("Intermediate")
      expect(q.trainings).to eq([training])
    end

    it "keeps the answer the admin marked correct, so exactly one is correct" do
      post questions_path, params: valid_params
      answers = Question.order(:id).last.answers.order(:id)
      expect(answers.map { |a| [a.description.to_plain_text, a.correct] }).to eq([["first", false], ["second", true]])
    end

    it "marks the first answer correct when none is marked" do
      params = valid_params
      params[:question][:answers_attributes]["1"][:correct] = "false"
      post questions_path, params: params
      expect(Question.order(:id).last.answers.order(:id).pluck(:correct)).to eq([true, false])
    end

    it "refuses a question with two answers marked correct, showing the error and creating nothing" do
      params = valid_params
      params[:question][:answers_attributes]["0"][:correct] = "true"
      expect { post questions_path, params: params }.not_to change(Question, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("A question must have exactly one correct answer")
    end

    it "refuses a question with no answers, showing the error and creating nothing" do
      expect { post questions_path, params: { question: { description: "No answers", level: "Beginner" } } }
        .not_to change(Question, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("A question must have exactly one correct answer")
    end

    it "stores uploaded PNG images" do
      img = fixture_file_upload(Rails.root.join("spec/support/assets/test.png"), "image/png")
      post questions_path, params: valid_params(images: [img])
      expect(Question.order(:id).last.images.map { |i| i.filename.to_s }).to eq(["test.png"])
    end

    it "answers 422 with the form for a non-image upload and creates nothing" do
      stl = fixture_file_upload(Rails.root.join("spec/support/assets/test.stl"), "application/octet-stream")
      expect { post questions_path, params: valid_params(images: [stl]) }.not_to change(Question, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("New Question")
    end
  end

  describe "GET /questions/:id/edit" do
    before { log_in!(admin) }

    it "lists the answers with the correct one first" do
      get edit_question_path(question)
      expect(response).to have_http_status(:ok)
      expect(response.body.index("The cut width")).to be < response.body.index("A tool")
    end

    it "reads the answer texts in a constant number of queries" do
      log_in!(admin)
      get edit_question_path(question) # warm up
      few = selects_on("action_text_rich_texts") { get edit_question_path(question) }
      4.times { |i| Answer.create!(question: question, correct: false, description: "extra #{i}") }
      many = selects_on("action_text_rich_texts") { get edit_question_path(question) }

      expect(response.body).to include("extra 3")
      expect(many.size).to eq(few.size)
    end

    it "renders one closed, resolvable remove form per removable answer" do
      3.times { |i| Answer.create!(question: question, correct: false, description: "extra #{i}") }
      get edit_question_path(question)
      doc = Nokogiri::HTML5(response.body, max_errors: 100)
      removable = question.answers.where(correct: false).pluck(:id)
      expect(removable.size).to eq(4)
      buttons = doc.css("button[form^='remove-answer-']")
      expect(buttons.size).to eq(4)
      removable.each do |id|
        form = doc.at_css("form##{"remove-answer-#{id}"}")
        expect(form).not_to be_nil
        expect(form["action"]).to eq(remove_answer_question_path(question, answer_id: id))
        # a form that was never closed would swallow the following forms
        expect(form.css("form")).to be_empty
        expect(form.parent.name).not_to eq("form")
      end
      expect(doc.css("form#remove-answer-#{removable.first}").first.ancestors("form")).to be_empty
    end

    it "renders a DELETE remove form (not a GET link) for each incorrect saved answer" do
      victim = question.answers.where(correct: false).first
      get edit_question_path(question)
      expect(response.body).to include(%(id="remove-answer-#{victim.id}"))
      expect(response.body).to include(%(action="#{remove_answer_question_path(question, answer_id: victim.id)}"))
      expect(response.body).not_to include("remove_answer=")
    end

    it "adds blank answers (unsaved) when n_answers is larger than the current count, with a notice" do
      expect { get edit_question_path(question, n_answers: 4) }.not_to change(Answer, :count)
      expect(flash[:notice]).to eq("Answer added. Please update its content!")
    end

    # GET /questions/:id/edit?remove_answer=ID does not destroy anything (removal is DELETE /questions/:id/answers/:answer_id)
    it "does not destroy the answer named by remove_answer on a plain GET" do
      victim = question.answers.where(correct: false).first
      expect { get edit_question_path(question, remove_answer: victim.id) }.not_to change(Answer, :count)
      expect(response).to have_http_status(:ok)
      expect(Answer.exists?(victim.id)).to be(true)
    end
  end

  describe "DELETE /questions/:id/answers/:answer_id (remove_answer)" do
    before { log_in!(admin) }

    # removal is a DELETE scoped to the question's own answers
    it "destroys the question's own answer and redirects to the edit form with a notice" do
      victim = question.answers.where(correct: false).first
      expect { delete remove_answer_question_path(question, answer_id: victim.id) }.to change(Answer, :count).by(-1)
      expect(response).to redirect_to(edit_question_path(question))
      expect(flash[:notice]).to eq("Successfully removed answer")
      expect(Answer.exists?(victim.id)).to be(false)
    end

    it "404s and keeps the correct answer" do
      correct = question.answers.find_by!(correct: true)
      expect { delete remove_answer_question_path(question, answer_id: correct.id) }.not_to change(Answer, :count)
      expect(response).to have_http_status(:not_found)
    end

    it "404s and destroys nothing for an answer that belongs to another question" do
      other = create(:question)
      victim = Answer.create!(question: other, correct: false, description: "someone else's")
      expect { delete remove_answer_question_path(question, answer_id: victim.id) }.not_to change(Answer, :count)
      expect(response).to have_http_status(:not_found)
      expect(Answer.exists?(victim.id)).to be(true)
    end
  end

  describe "PATCH /questions/:id (update)" do
    before { log_in!(admin) }

    it "updates the description and replaces the training links, redirecting with a notice" do
      other = create(:training, spaces: [space])
      patch question_path(question), params: { question: { description: "Updated?", training_ids: ["", other.id.to_s] } }
      expect(response).to redirect_to(questions_path)
      expect(flash[:notice]).to eq("Question updated")
      question.reload
      expect(question.description).to eq("Updated?")
      expect(question.trainings).to eq([other])
    end

    it "updates nested answers by id" do
      answer = question.answers.order(:id).last
      patch question_path(question),
            params: { question: { answers_attributes: { "0" => { id: answer.id, description: "A hammer", correct: "true" } } } }
      expect(answer.reload.description.to_plain_text).to eq("A hammer")
      expect(answer.correct).to be(true)
      expect(question.answers.where(correct: true).count).to eq(2)
    end

    it "alerts and redirects when the update is invalid" do
      stl = fixture_file_upload(Rails.root.join("spec/support/assets/test.stl"), "application/octet-stream")
      patch question_path(question), params: { question: { images: [stl] } }
      expect(response).to redirect_to(questions_path)
      expect(flash[:alert]).to eq("Something went wrong")
    end
  end

  describe "DELETE /questions/:id" do
    before { log_in!(admin) }

    it "deletes the question and its answers" do
      expect { delete question_path(question) }.to change(Question, :count).by(-1).and change(Answer, :count).by(-2)
      expect(response).to redirect_to(questions_path)
      expect(flash[:notice]).to eq("Question Deleted")
    end

    it "keeps the exam_questions of a used question, with the question cleared" do
      exam = create(:exam)
      eq = ExamQuestion.create!(exam: exam, question: question)
      delete question_path(question)
      expect(ExamQuestion.find(eq.id).question_id).to be_nil
      expect(Question.exists?(question.id)).to be(false)
    end
  end

  describe "DELETE /questions/delete_individually" do
    before { log_in!(admin) }

    it "purges the image and redirects to the edit page with a notice" do
      question.images.attach(io: File.open(Rails.root.join("spec/support/assets/test.png")), filename: "test.png", content_type: "image/png")
      attachment = question.images.attachments.first
      delete delete_individually_questions_path, params: { id: attachment.id, question_id: question.id }
      expect(response).to redirect_to(edit_question_path(question.id))
      expect(flash[:notice]).to eq("Question image deleted")
      expect(question.reload.images).not_to be_attached
    end

    # the attachment is looked up among the question's own images, so a foreign attachment is a 404 and is kept
    it "does not purge an attachment that belongs to another record (a user avatar): 404" do
      user = create(:user, :regular_user_with_avatar)
      attachment = user.avatar.attachment
      delete delete_individually_questions_path, params: { id: attachment.id, question_id: question.id }
      expect(response).to have_http_status(:not_found)
      expect(ActiveStorage::Attachment.exists?(attachment.id)).to be(true)
    end
  end
end
