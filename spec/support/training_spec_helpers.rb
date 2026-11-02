# frozen_string_literal: true

# Shared helpers for the Training characterization specs (chunk 12).
#
# Request specs sign in through the real login POST (the session store is
# custom, there is no Devise), as in sub_space_booking_roles_request_spec.rb.
module TrainingSpecHelpers
  PASSWORD = "asa32A353#"

  def log_in!(user)
    post login_authentication_path, params: { username_email: user.username, password: PASSWORD }
    expect(response).to redirect_to(root_path)
    user
  end

  # Signs in a user of the given role (or nobody for :guest) and returns it.
  def sign_in_as(role, **attrs)
    return nil if role == :guest

    trait = { regular: :regular_user, staff: :staff, admin: :admin, volunteer: :volunteer_with_dev_program }.fetch(role)
    log_in!(create(:user, trait, **attrs))
  end

  def deliveries
    ActionMailer::Base.deliveries
  end

  def expect_login_redirect(path = nil)
    expect(response).to have_http_status(:found)
    expect(response.location).to start_with("http://www.example.com/login")
    expect(CGI.unescape(response.location)).to include("back_to=#{path}") if path
  end

  # Builds a training session with N users enrolled and `questions` questions
  # (each with one correct and three wrong answers) at the session's level.
  def build_exam_fixture(level: "Beginner", question_count: 3, user: nil)
    trainer = create(:user, :staff)
    training = create(:training)
    session = create(:training_session, user: trainer, training: training, level: level)
    user ||= create(:user, :regular_user)
    session.users << user
    questions = Array.new(question_count) do
      q = create(:question, level: level)
      training.questions << q
      correct = Answer.create!(question: q, correct: true, description: "right #{q.id}")
      wrongs = Array.new(3) { |i| Answer.create!(question: q, correct: false, description: "wrong #{i}") }
      { question: q, correct: correct, wrongs: wrongs }
    end
    { trainer: trainer, training: training, session: session, user: user, questions: questions }
  end
end

RSpec.configure do |config|
  config.include TrainingSpecHelpers, type: :request
  config.include TrainingSpecHelpers, type: :mailer
end

module TrainingSpecHelpers
  # Request specs render exceptions through the debug page (status mapped from
  # the exception class); the message is HTML-escaped there.
  def error_text
    CGI.unescapeHTML(response.body)
  end
end
