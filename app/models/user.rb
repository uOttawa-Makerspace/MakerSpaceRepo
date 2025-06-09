# frozen_string_literal: true

class User < ApplicationRecord
  include BCrypt
  include ActiveModel::Serialization
  belongs_to :space, optional: true
  has_one :rfid, dependent: :destroy
  has_many :upvotes, dependent: :destroy
  has_many :comments, dependent: :destroy
  has_and_belongs_to_many :repositories, dependent: :destroy
  has_many :certifications,
           class_name: "Certification",
           dependent: :destroy
  has_many :demotion_staff,
           class_name: "Certification",
           foreign_key: "demotion_staff_id",
           dependent: :destroy
  has_many :lab_sessions, dependent: :destroy
  has_and_belongs_to_many :training_sessions
  accepts_nested_attributes_for :repositories
  has_many :project_proposals
  has_many :project_joins, dependent: :destroy
  has_many :printer_sessions, dependent: :destroy
  has_many :volunteer_hours
  has_many :volunteer_tasks
  has_many :volunteer_task_joins
  has_many :training_sessions
  has_many :announcements
  has_many :questions
  has_many :exams
  has_many :exam_responses
  has_many :print_orders
  has_many :volunteer_task_requests
  has_many :cc_moneys, dependent: :destroy
  has_many :badges, dependent: :destroy
  has_many :programs, dependent: :destroy
  has_and_belongs_to_many :proficient_projects
  # has_and_belongs_to_many :learning_modules
  has_many :orders, dependent: :destroy
  has_many :order_items, through: :orders
  has_many :discount_codes, dependent: :destroy
  has_one_attached :avatar
  has_many :project_kits, dependent: :destroy
  has_many :learning_module_tracks
  has_many :shadowing_hours
  has_many :staff_spaces, dependent: :destroy
  has_many :staff_availabilities, dependent: :destroy
  has_and_belongs_to_many :shifts, dependent: :destroy
  has_many :job_orders, dependent: :destroy
  has_many :job_order_statuses
  has_many :coupon_codes, dependent: :destroy # GoDaddy temp replacement for discount codes
  has_one :key_request,
          class_name: "KeyRequest",
          dependent: :destroy
  has_many :key_transactions, dependent: :destroy
  has_one :key_certification, dependent: :destroy
  has_many :keys, class_name: "Key"
  has_many :team_memberships, dependent: :destroy
  has_many :teams, through: :team_memberships
  has_many :space_manager_joins, dependent: :destroy
  has_many :supervised_spaces, through: :space_manager_joins, source: :space
  has_many :staff_spaces, dependent: :destroy
  has_many :spaces, through: :staff_spaces
  has_many :printer_issues # Don't delete issues when a user is deleted
  has_many :locker_rentals, foreign_key: "rented_by"

  MAX_AUTH_ATTEMPTS = 5

  validates :avatar,
            file_content_type: {
              allow: %w[image/jpeg image/png image/webp image/gif],
              if: -> { avatar.attached? }
            }

  validates :name, presence: true, length: { maximum: 50 }

  validates :username,
            presence: true,
            uniqueness: true,
            format: {
              with: /\A[a-zA-ZÀ-ÿ\d]*\z/
            },
            length: {
              maximum: 20
            }

  validates :email, presence: true, on: :create, uniqueness: true, email: true

  validates :how_heard_about_us, length: { maximum: 250 }

  validates :read_and_accepted_waiver_form,
            inclusion: {
              in: [true]
            },
            on: :create

  validates :password,
            confirmation: true,
            presence: true,
            password: {
              name: :username,
              email: :email
            }

  validates :gender,
            presence: true,
            inclusion: {
              in: [
                "Male",
                "Female",
                "Other",
                "Prefer not to specify",
                "unknown"
              ]
            }

  validates :faculty,
            presence: true,
            if: :student?,
            inclusion: {
              in: [
                "Engineering",
                "Social Sciences",
                "Education",
                "Arts",
                "Medicine",
                "Law",
                "Health Sciences",
                "Science",
                "Telfer School of Management"
              ]
            }

  before_validation do |user|
    case user.faculty # Translate faculty
    when "Arts"
      user.faculty = "Arts"
    when "Éducation"
      user.faculty = "Education"
    when "Génie"
      user.faculty = "Engineering"
    when "Sciences de la santé"
      user.faculty = "Health Sciences"
    when "Droit civil"
      user.faculty = "Civil Law"
    when "Droit commun"
      user.faculty = "Common Law"
    when "Droit"
      user.faculty = "Law"
    when "Médecine"
      user.faculty = "Medicine"
    when "Sciences"
      user.faculty = "Science"
    when "Sciences sociales"
      user.faculty = "Social Sciences"
    when "École de gestion Telfer"
      user.faculty = "Telfer School of Management"
    end
  end

  validates :role,
            inclusion: {
              in: %w[regular_user admin staff volunteer]
            },
            allow_blank: true

  validates :program, presence: true, if: :student?

  validates :year_of_study, presence: true, if: :student?

  validates :identity,
            presence: true,
            inclusion: {
              in: %w[
                grad
                undergrad
                international_grad
                international_undergrad
                faculty_member
                community_member
                unknown
              ]
            }

  validates :student_id,
            format: {
              with: /[0-9]/,
              message: "Student id must be numeric and 9 digits"
            },
            length: {
              is: 9
            },
            allow_blank: true,
            presence: true,
            if: :student?

  default_scope { where(deleted: false) }
  scope :no_waiver_users, -> { where("read_and_accepted_waiver_form = false") }
  scope :between_dates_picked,
        ->(start_date, end_date) {
          where("created_at BETWEEN ? AND ? ", start_date, end_date)
        }
  scope :frequency_between_dates,
        ->(start_date, end_date) {
          joins(lab_sessions: :space).where(
            "lab_sessions.sign_in_time BETWEEN ? AND ? AND spaces.name = ?",
            start_date,
            end_date,
            "Makerspace"
          )
        }
  scope :active, -> { where(active: true) }
  scope :unknown_identity, -> { where(identity: "unknown") }
  scope :created_at_month,
        ->(month) { where("DATE_PART('month', created_at) = ?", month) }
  scope :not_created_this_year,
        -> {
          where.not(
            created_at: DateTime.now.beginning_of_year..DateTime.now.end_of_year
          )
        }
  scope :created_this_year,
        -> {
          where(
            created_at: DateTime.now.beginning_of_year..DateTime.now.end_of_year
          )
        }
  scope :staff, -> { where(role: %w[admin staff]) }
  scope :students,
        -> {
          where(
            identity: %w[
              undergrad
              grad
              international_undergrad
              international_grad
            ]
          )
        }
  scope :volunteers,
        -> {
          joins(:programs).where(programs: { program_type: Program::VOLUNTEER })
        }

  def token(exp = 14.days.from_now.to_i)
    JWT.encode(
      { user_id: id, exp: exp },
      Rails.application.credentials.secret_key_base,
      "HS256"
    )
  end

  def display_avatar
    avatar.attached? ? avatar : "default-avatar.png"
  end

  def self.authenticate(username_email, password)
    user = User.username_or_email(username_email)
    return nil unless user
    if user.pword == password
      user.update(auth_attempts: 0)
      return user
    end
    user.update(auth_attempts: user.auth_attempts + 1)
    if user.auth_attempts >= MAX_AUTH_ATTEMPTS
      user.update(locked: true)
      user.update(locked_until: 5.minutes.from_now)
      user_hash = Rails.application.message_verifier("unlock").generate(user.id)
      MsrMailer.unlock_account(user, user_hash).deliver_now
    end
    nil
  end

  def self.username_or_email(username_email)
    User
      .where(username: username_email)
      .or(User.where("lower(email) = ?", username_email.downcase))
      .first
  end

  def pword
    @pword ||= Password.new(password)
  end

  def pword=(new_password)
    @pword = Password.create(new_password)
    self.password = @pword
    self.password_confirmation = @pword
  end

  def has_avatar?
    avatar.attached?
  end

  def student?
    ["grad", "undergrad", "international_grad", "international_undergrad"].include?(identity)
  end

  def admin?
    role.eql?("admin")
  end

  def staff?
    role.eql?("staff") || role.eql?("admin")
  end

  def volunteer?
    programs.pluck(:program_type).include?(Program::VOLUNTEER)
  end

  def volunteer_program?
    programs.pluck(:program_type).include?(Program::VOLUNTEER)
  end

  def dev_program?
    programs.pluck(:program_type).include?(Program::DEV_PROGRAM)
  end

  def teams_program?
    programs.pluck(:program_type).include?(Program::TEAMS)
  end

  def staff_in_space?
    staff_spaces.count > 0
  end

  def internal?
    ["faculty_member", "grad", "undergrad", "international_grad", "international_undergrad"].include?(identity)
  end

  def self.to_csv(attributes)
    CSV.generate { |csv| attributes.each { |row| csv << row } }
  end

  def location
    return "no sign in yet" if lab_sessions.last.equal? nil

    lab_sessions.last.space.name
  end

  def get_certifications_names
    cert = []
    certifications.each { |c| cert << c.training.name_en }
    cert
  end

  def get_volunteer_tasks_from_volunteer_joins
    volunteer_tasks = []
    vtjs = volunteer_task_joins.active
    vtjs.each { |vtj| volunteer_tasks << vtj.volunteer_task }
    volunteer_tasks
  end

  def get_total_cc
    cc_moneys.sum(:cc)
  end

  def get_total_hours
    volunteer_hours.approved.sum(:total_time)
  end

  def get_badges(training_id)
    training_ids = []
    certifications.each do |cert|
      training_ids << cert.training_session.training.id
    end
    if training_ids.include?(training_id)
        "badges/bronze.png"
      else
        "badges/none.png"
      end
    
  end

  def remaining_trainings
    trainings = []
    certifications.each { |cert| trainings << cert.training.id }
    Training.all.where.not(id: trainings)
  end

  def return_program_status
    { volunteer: volunteer_program?, dev: dev_program?, teams: teams_program? }
  end

  def update_wallet
    update(wallet: get_total_cc)
  end

  def has_required_trainings?(training_requirements)
    user_trainings_set = training_sessions.pluck(:training_id).to_set
    training_requirements_set = training_requirements.pluck(:training_id).to_set
    training_requirements_set.subset?(user_trainings_set)
  end

  def highest_badge(training)
    badges =
      
        certifications
        .joins(:training_session)
        .where(training_sessions: { training_id: training.id })
    if badges.where(training_sessions: { level: "Advanced" }).present?
      badge = badges.where(training_sessions: { level: "Advanced" }).last
    elsif badges.where(training_sessions: { level: "Intermediate" }).present?
      badge = badges.where(training_sessions: { level: "Intermediate" }).last
    elsif badges.where(training_sessions: { level: "Beginner" }).present?
      badge = badges.where(training_sessions: { level: "Beginner" }).last
    end
    badge
  end

  def department
    # HACK: some programs include words like 'in' that aren't
    # in the program list. try to clean up before processing
    # So this might return nil or 'Non-Engineering' too
    program_alt = program.gsub(" in", "")
    UniProgram
      .where(program: program)
      .or(UniProgram.where(program: program_alt))
      .take
      &.department
  end

  def engineering?
    student? and department != "Non-Engineering"
  end

  def identity_readable
    if student?
      year = year_of_study.to_s
      if I18n.locale == :fr
        year += case year.last
        when "1"
          "ère"
        else
          "ème"
                end
      elsif I18n.locale == :en
        year = year.to_i.ordinalize
      end

      if engineering?
        # department + ' ' unless department.nil?
        "#{year} #{I18n.t "year"} #{department&.+ " "}#{identity.titleize}uate"
      else
        "#{year} #{I18n.t "year"} #{identity}uate".titleize
      end
    else
      identity.titleize
    end
  end
end
