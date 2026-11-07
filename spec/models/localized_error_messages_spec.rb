# frozen_string_literal: true

require "rails_helper"

# The custom validation messages of the models come from locale keys: English reads as it always did and French
# users get French text (not "Translation missing" and not the English literal).
RSpec.describe "Localized model error messages" do
  def messages(record, attribute, locale, context = nil)
    I18n.with_locale(locale) do
      record.valid?(context)
      record.errors[attribute]
    end
  end

  def messages_after_save(record, locale)
    I18n.with_locale(locale) do
      record.errors.clear
      record.save
      record.errors[:base]
    end
  end

  def expect_messages(record, attribute, english, french, context = nil)
    expect(messages(record, attribute, :en, context)).to include(english)
    expect(messages(record, attribute, :fr, context)).to include(french)
    expect(french).not_to eq(english)
  end

  let(:user) { create(:user) }

  describe KeyRequest do
    subject(:request) { KeyRequest.new(status: :waiting_for_approval) }

    it "localizes presence, phone, contact, rules and question messages" do
      request.assign_attributes(phone_number: "abc", read_lab_rules: false)
      expect_messages(request, :user, "A user is required", "Un utilisateur est requis")
      expect_messages(request, :supervisor, "A supervisor is required", "Un superviseur est requis")
      expect_messages(request, :space, "A space is required", "Un espace est requis")
      expect_messages(request, :user_status, "A user status is required", "Un statut d'utilisateur est requis")
      expect_messages(request, :phone_number, "only allows numbers, parentheses, dashes, spaces, dots, and +",
                      "n'accepte que des chiffres, des parenthèses, des tirets, des espaces, des points et le signe +")
      expect_messages(request, :student_number, "student number and emergency contact is required",
                      "le numéro d'étudiant et le contact d'urgence sont requis")
      expect_messages(request, :read_lab_rules, "You must agree to all the rules and policies",
                      "Vous devez accepter toutes les règles et politiques")
      expect_messages(request, :question_3, "Question 3 is required", "La question 3 est requise")
    end
  end

  describe Key do
    it "localizes the held-key, number and keycode messages" do
      space = create(:space)
      create(:key, space: space, number: "7")
      held = Key.new(status: :held, key_type: :regular, space: space, number: "7")
      expect_messages(held, :user, "A user is required if the key is held", "Un utilisateur est requis si la clé est détenue")
      expect_messages(held, :supervisor, "A supervisor is required if the key is held",
                      "Un superviseur est requis si la clé est détenue")
      expect_messages(held, :number, "A key already has that number", "Une clé porte déjà ce numéro")
      expect_messages(Key.new(key_type: :regular), :space, "A space is required", "Un espace est requis")
      keycard = Key.new(key_type: :keycard)
      expect_messages(keycard, :number, "A key number is required", "Un numéro de clé est requis")
      expect_messages(keycard, :custom_keycode, "A keycode is required", "Un code de clé est requis")
    end
  end

  it "localizes the coupon price message" do
    expect_messages(CouponCode.new(cc_cost: -1), :cc_cost, "must be a number of CC points (0 or more)",
                    "doit être un nombre de points CC (0 ou plus)")
  end

  describe Program do
    it "localizes the user and type messages" do
      create(:program, :development_program, user_id: user.id)
      program = Program.new(user_id: user.id, program_type: Program::DEV_PROGRAM)
      expect_messages(program, :user, "An user can only join a program once",
                      "Un utilisateur ne peut se joindre à un programme qu'une seule fois")
      blank = Program.new
      expect_messages(blank, :user, "A user is required.", "Un utilisateur est requis.")
      expect_messages(blank, :program_type,
                      "The type of the program is required. Either 'Volunteer Program', 'Development Program', or 'Teams Program'",
                      "Le type de programme est requis. Soit « Volunteer Program », « Development Program » ou « Teams Program »")
    end
  end

  it "localizes the rfid card number message" do
    expect_messages(Rfid.new, :card_number, "Card number is required.", "Le numéro de carte est requis.")
  end

  it "localizes the team name message" do
    expect_messages(Team.new, :name, "A team name is required.", "Un nom d'équipe est requis.")
  end

  it "localizes the certification messages" do
    expect_messages(Certification.new(level: "x"), :user, "A user is required.", "Un utilisateur est requis.")
    expect_messages(Certification.new(level: "x"), :level, "A level is required.", "Un niveau est requis.")
  end

  it "localizes the space and sub space name messages" do
    create(:space, name: "Taken Lab")
    expect_messages(Space.new(name: ""), :name, "A name is required for the space", "Un nom est requis pour l'espace")
    expect_messages(Space.new(name: "Taken Lab"), :name, "Space already exists", "Cet espace existe déjà")
    expect_messages(SubSpace.new, :name, "A name is required for the space", "Un nom est requis pour l'espace")
  end

  it "localizes the required training message" do
    expect_messages(RequireTraining.new, :training_id, "A training must be selected", "Une formation doit être sélectionnée")
  end

  it "localizes the training session messages" do
    session = TrainingSession.new(user: create(:user, role: "regular_user"))
    expect_messages(session, :training, "A training subject is required", "Un sujet de formation est requis")
    expect_messages(TrainingSession.new, :user, "A trainer is required", "Un formateur est requis")
    expect_messages(TrainingSession.new(level: ""), :level, "A level is required", "Un niveau est requis")
    expect_messages(session, :user, "must be staff", "doit faire partie du personnel")
    I18n.with_locale(:fr) do
      session.valid?
      expect(session.errors.full_messages).to include("Formateur doit faire partie du personnel")
    end
  end

  it "localizes the project prerequisite message" do
    existing = create(:project_requirement)
    duplicate = ProjectRequirement.new(proficient_project: existing.proficient_project,
                                       required_project: existing.required_project)
    expect_messages(duplicate, :proficient_project_id, "This project is already a pre-requisite",
                    "Ce projet est déjà un préalable")
  end

  it "localizes the time period date message" do
    period = TimePeriod.new(start_date: Date.new(2026, 5, 2), end_date: Date.new(2026, 5, 1))
    expect_messages(period, :end_date, "must not be before the start date", "ne doit pas être antérieure à la date de début")
  end

  it "localizes the space manager admin message" do
    join = SpaceManagerJoin.new(user: create(:user, role: "regular_user"))
    expect_messages(join, :base, "User must be an admin", "L'utilisateur doit être administrateur")
  end

  it "localizes the question answer message" do
    expect_messages(Question.new, :base, "A question must have exactly one correct answer",
                    "Une question doit avoir exactement une bonne réponse", :question_form)
  end

  it "localizes the quick access link messages" do
    admin = create(:user, :admin)
    QuickAccessLink.create!(user: admin, name: "Faq", path: "/faq")
    expect_messages(QuickAccessLink.new(user: admin, name: "Again", path: "/faq"), :path,
                    "You already have a quick access link to that location",
                    "Vous avez déjà un lien d'accès rapide vers cet emplacement")
    expect_messages(QuickAccessLink.new(user: admin, name: "Me", path: "/#{admin.username}"), :path,
                    "cannot point to a user", "ne peut pas pointer vers un utilisateur")
    expect_messages(QuickAccessLink.new(user: admin, name: "Bad", path: "/no/such/route/at/all/xyz"), :path,
                    "must be a valid path", "doit être un chemin valide")
  end

  describe LockerRental do
    it "localizes the one request and cancelled state messages" do
      renter = create(:user)
      create(:locker_rental, :reviewing, rented_by: renter)
      expect_messages(build(:locker_rental, :reviewing, rented_by: renter), :rented_by,
                      "already has a request under review", "a déjà une demande en attente de révision")

      rental = create(:locker_rental, :active)
      rental.update!(state: :cancelled)
      rental.state = :active
      expect_messages(rental, :state,
                      "cannot change from cancelled except back to awaiting payment, or to active by staff",
                      "ne peut pas passer de « Terminée » à un autre état, sauf pour revenir à « Attendre le paiement » ou pour passer à « Actif » par le personnel")
    end
  end

  it "localizes the order item messages" do
    item = OrderItem.new(quantity: 1)
    expect_messages(item, :proficient_project, "is not valid", "n'est pas valide")
    expect_messages(item, :order, "is not a valid order.", "n'est pas une commande valide.")
  end

  it "localizes the job task service message" do
    task = JobTask.new(job_service: create(:job_service))
    expect_messages(task, :job_service, "is not available for this task", "n'est pas disponible pour cette tâche")
  end

  it "localizes the reader identifier message" do
    reader = PiReader.new(pi_mac_address: "aa bb")
    expect_messages(reader, :pi_mac_address,
                    "must be at most 64 characters with no spaces, control or invisible characters",
                    "doit contenir au plus 64 caractères, sans espaces ni caractères de contrôle ou invisibles")
  end

  it "localizes the refresh token expiry message" do
    token = ApiRefreshToken.issue!(user)
    token.expires_at = token.family_expires_at + 1.day
    expect_messages(token, :expires_at, "must not be after the family cap",
                    "ne doit pas dépasser la limite de la famille de jetons")
  end

  it "localizes the help submission message" do
    allow_any_instance_of(GithubIssuesService).to receive(:create_issue).and_return({ number: nil })
    attrs = { name: "Pat", email: "pat@example.test", subject: "A long enough subject", comments: "Something broke" }
    expect(messages_after_save(Help.new(attrs), :en)).to include("Internal error while submitting issue.")
    expect(messages_after_save(Help.new(attrs), :fr)).to include("Erreur interne lors de la soumission du problème.")
  end

  it "localizes the booking time and volunteer photo messages" do
    booking = SubSpaceBooking.new(start_time: Time.zone.parse("2027-03-03 10:00"), end_time: Time.zone.parse("2027-03-03 10:00"))
    expect(I18n.with_locale(:en) { booking.valid?; booking.errors.full_messages })
      .to include("Expiration date Start Time needs to be before end time")
    expect(I18n.with_locale(:fr) { booking.valid?; booking.errors.full_messages })
      .to include("Date d'expiration L'heure de début doit être antérieure à l'heure de fin")
    task = create(:volunteer_task)
    6.times { Photo.new(volunteer_task: task).save(validate: false) }
    expect_messages(task, :photos, " can't exceed 5 photos", "ne peut pas dépasser 5 photos")
  end

  describe "titles and projects" do
    it "localizes the learning module title messages" do
      existing = create(:learning_module)
      expect_messages(LearningModule.new(title: ""), :title, "A title is required.", "Un titre est requis.")
      expect_messages(LearningModule.new(title: existing.title, training: existing.training), :title,
                      "Title already exists", "Ce titre existe déjà")
    end

    it "localizes the proficient project title messages" do
      existing = create(:proficient_project)
      expect_messages(ProficientProject.new(title: ""), :title, "A title is required.", "Un titre est requis.")
      expect_messages(ProficientProject.new(title: existing.title), :title, "Title already exists", "Ce titre existe déjà")
    end

    it "localizes the repository title, password and photo messages" do
      existing = create(:repository)
      expect_messages(Repository.new(title: ""), :title, "Project title is required.", "Le titre du projet est requis.")
      expect_messages(Repository.new(title: existing.title, user_id: existing.user_id), :title,
                      "Project title is already in use.", "Le titre du projet est déjà utilisé.")
      expect_messages(Repository.new(share_type: "private"), :password,
                      "Password is required for private projects", "Un mot de passe est requis pour les projets privés")
      expect_messages(Repository.new, :photos, "Must have between 1 and 5 photos", "Doit avoir entre 1 et 5 photos")
    end
  end

  describe "staff and event calendars" do
    let(:weekly) { "FREQ=WEEKLY;INTERVAL=1" }
    let(:later) { 2.days.from_now.change(usec: 0) }

    it "localizes the unavailability time and recurrence messages" do
      record = StaffUnavailability.new(user: user, start_time: later, end_time: later - 1.hour, recurrence_rule: weekly)
      expect_messages(record, :start_time, "must be before the end time", "doit être antérieure à l'heure de fin")
      expect_messages(record, :recurrence_rule, "must include days of the week when using weekly frequency",
                      "doit inclure des jours de la semaine lorsque la fréquence est hebdomadaire")
      I18n.with_locale(:fr) do
        record.valid?
        expect(record.errors.full_messages).to include("Heure de début doit être antérieure à l'heure de fin")
      end
    end

    it "localizes the event time and recurrence messages" do
      event = Event.new(start_time: later, end_time: later - 1.hour, recurrence_rule: weekly)
      expect_messages(event, :start_time, "must be before the end time", "doit être antérieure à l'heure de fin")
      expect_messages(event, :recurrence_rule, "must include days of the week when using weekly frequency",
                      "doit inclure des jours de la semaine lorsque la fréquence est hebdomadaire")
    end

    it "localizes the external calendar link message" do
      record = StaffExternalUnavailability.new(user: user, ics_url: "ftp://example.test/cal.ics")
      expect_messages(record, :ics_url, "must be an http or https link", "doit être un lien http ou https")
    end

    it "localizes the single open hours calendar message" do
      space = create(:space)
      StaffNeededCalendar.create!(space: space, calendar_url: "https://x.test/a.ics", role: "open_hours")
      second = StaffNeededCalendar.new(space: space, role: "open_hours")
      expect_messages(second, :space_id, "can only have one open_hours calendar",
                      "ne peut avoir qu'un seul calendrier d'heures d'ouverture")
    end
  end
end
