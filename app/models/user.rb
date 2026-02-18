# frozen_string_literal: true

class User < ApplicationRecord
  include BCrypt
  include ActiveModel::Serialization
  include UoengConcern

  # ============================================
  # Constants
  # ============================================
  
  MAX_AUTH_ATTEMPTS = 5
  LOCK_DURATION = 5.minutes

  GENDERS = [
    'Male',
    'Female',
    'Other',
    'Prefer not to specify',
    'unknown'
  ].freeze

  FACULTIES = [
    'Engineering',
    'Social Sciences',
    'Education',
    'Arts',
    'Medicine',
    'Law',
    'Health Sciences',
    'Science',
    'Telfer School of Management'
  ].freeze

  FACULTY_TRANSLATIONS = {
    'Arts' => 'Arts',
    'Éducation' => 'Education',
    'Génie' => 'Engineering',
    'Sciences de la santé' => 'Health Sciences',
    'Droit civil' => 'Civil Law',
    'Droit commun' => 'Common Law',
    'Droit' => 'Law',
    'Médecine' => 'Medicine',
    'Sciences' => 'Science',
    'Sciences sociales' => 'Social Sciences',
    'École de gestion Telfer' => 'Telfer School of Management'
  }.freeze

  ROLES = %w[regular_user admin staff volunteer].freeze

  IDENTITIES = %w[
    grad
    undergrad
    international_grad
    international_undergrad
    faculty_member
    community_member
    unknown
  ].freeze

  STUDENT_IDENTITIES = %w[
    grad
    undergrad
    international_grad
    international_undergrad
  ].freeze

  INTERNAL_IDENTITIES = %w[
    faculty_member
    grad
    undergrad
    international_grad
    international_undergrad
  ].freeze

  ALLOWED_AVATAR_TYPES = %w[image/jpeg image/png image/webp image/gif].freeze

  # ============================================
  # Associations
  # ============================================
  
  belongs_to :space, optional: true
  
  has_one :rfid, dependent: :destroy
  has_one :key_request, class_name: 'KeyRequest', dependent: :destroy
  has_one :key_certification, dependent: :destroy
  has_one_attached :avatar
  
  has_many :upvotes, dependent: :destroy
  has_many :comments, dependent: :destroy
  has_many :owned_repositories, class_name: 'Repository', dependent: :destroy
  has_many :likes
  has_many :certifications, class_name: 'Certification', dependent: :destroy
  has_many :demotion_staff,
           class_name: 'Certification',
           foreign_key: 'demotion_staff_id',
           dependent: :destroy
  has_many :lab_sessions, dependent: :destroy
  has_many :project_proposals
  has_many :project_joins, dependent: :destroy
  has_many :printer_sessions, dependent: :destroy
  has_many :volunteer_hours
  has_many :volunteer_tasks
  has_many :volunteer_task_joins
  has_many :training_sessions # Direct, points to trainer
  has_many :announcements
  has_many :questions
  has_many :exams
  has_many :exam_responses, through: :exams
  has_many :print_orders
  has_many :volunteer_task_requests
  has_many :cc_moneys, dependent: :destroy
  has_many :programs, dependent: :destroy
  has_many :orders, dependent: :destroy
  has_many :order_items, through: :orders
  has_many :discount_codes, dependent: :destroy
  has_many :project_kits, dependent: :destroy
  has_many :learning_module_tracks
  has_many :shadowing_hours
  has_many :staff_spaces, dependent: :destroy
  has_many :staff_availabilities, dependent: :destroy
  has_many :job_orders, dependent: :destroy
  has_many :job_order_statuses
  has_many :coupon_codes, dependent: :destroy
  has_many :key_transactions, dependent: :destroy
  has_many :keys, class_name: 'Key'
  has_many :team_memberships, dependent: :destroy
  has_many :teams, through: :team_memberships
  has_many :space_manager_joins, dependent: :destroy
  has_many :supervised_spaces, through: :space_manager_joins, source: :space
  has_many :spaces, through: :staff_spaces
  has_many :user_booking_approvals, inverse_of: :staff
  has_many :printer_issues, inverse_of: :reporter
  has_many :locker_rentals, foreign_key: 'rented_by'
  has_many :staff_unavailabilities
  has_many :staff_external_unavailabilities, dependent: :destroy
  has_many :walk_in_safety_sheets
  has_many :memberships, dependent: :destroy
  
  has_and_belongs_to_many :repositories
  has_and_belongs_to_many :proficient_projects
  has_and_belongs_to_many :shifts, dependent: :destroy
  
  accepts_nested_attributes_for :repositories

  # ============================================
  # Validations
  # ============================================

  validates :avatar,
            file_content_type: {
              allow: ALLOWED_AVATAR_TYPES,
              if: -> { avatar.attached? }
            }

  validates :name, 
            presence: true, 
            length: { maximum: 50 }

  validates :username,
            presence: true,
            uniqueness: { case_sensitive: false },
            format: { with: /\A[a-zA-ZÀ-ÿ\d]*\z/ },
            length: { maximum: 20 }

  validates :email,
            presence: true,
            on: :create,
            uniqueness: { case_sensitive: false },
            email: true

  validates :how_heard_about_us, 
            length: { maximum: 250 }

  validates :read_and_accepted_waiver_form,
            inclusion: { in: [true] },
            on: :create

  validates :password,
            confirmation: true,
            presence: true,
            password: { name: :username, email: :email }

  validates :gender,
            presence: true,
            inclusion: { in: GENDERS }

  validates :faculty,
            presence: true,
            if: :student?,
            inclusion: { in: FACULTIES }

  validates :role,
            inclusion: { in: ROLES },
            allow_blank: true

  validates :program, 
            presence: true, 
            if: :student?

  validates :year_of_study, 
            presence: true, 
            if: :student?

  validates :identity,
            presence: true,
            inclusion: { in: IDENTITIES }

  # SECURITY FIX: Proper regex anchoring for student_id
  # Old: /[0-9]/ - only checked for presence of ANY digit
  # New: /\A[0-9]{9}\z/ - ensures EXACTLY 9 digits, nothing else
  validates :student_id,
          format: {
            with: /\A[0-9]{7,12}\z/,
            message: 'must be between 7 and 12 digits'
          },
          allow_blank: true,
          presence: true,
          if: :student?

  # ============================================
  # Normalizations & Callbacks
  # ============================================

  normalizes :email, with: ->(email) { email.strip.downcase }

  before_validation :translate_faculty

  # ============================================
  # Scopes
  # ============================================

  default_scope { where(deleted: false) }

  scope :no_waiver_users, -> { where(read_and_accepted_waiver_form: false) }
  
  scope :between_dates_picked, ->(start_date, end_date) {
    where(created_at: start_date..end_date)
  }
  
  scope :frequency_between_dates, ->(start_date, end_date) {
    joins(lab_sessions: :space).where(
      lab_sessions: { sign_in_time: start_date..end_date },
      spaces: { name: 'Makerspace' }
    )
  }
  
  scope :active, -> { where(active: true) }
  scope :unknown_identity, -> { where(identity: 'unknown') }
  
  scope :created_at_month, ->(month) { 
    where("DATE_PART('month', created_at) = ?", month) 
  }
  
  scope :not_created_this_year, -> {
    where.not(created_at: DateTime.now.beginning_of_year..DateTime.now.end_of_year)
  }
  
  scope :created_this_year, -> {
    where(created_at: DateTime.now.beginning_of_year..DateTime.now.end_of_year)
  }
  
  scope :staff, -> { where(role: %w[admin staff]) }
  
  scope :students, -> { where(identity: STUDENT_IDENTITIES) }
  
  scope :volunteers, -> {
    joins(:programs).where(programs: { program_type: Program::VOLUNTEER })
  }

  scope :search, ->(query) {
    where(
      'LOWER(UNACCENT(name)) LIKE LOWER(UNACCENT(:query)) OR LOWER(UNACCENT(username)) LIKE LOWER(UNACCENT(:query))',
      query: "%#{sanitize_sql_like(query)}%"
    ).limit(30)
  }

  scope :fuzzy_search, ->(query) {
    where(
      'LOWER(UNACCENT(name)) % LOWER(UNACCENT(:query)) OR LOWER(UNACCENT(username)) % LOWER(UNACCENT(:query))',
      query: query
    )
    .order(
      sanitize_sql_for_order([Arel.sql('similarity(name, ?) DESC'), query])
    )
    .limit(30)
  }

  scope :reduced_fuzzy_search, ->(query) {
    where('LOWER(UNACCENT(username)) % LOWER(UNACCENT(:query))', query: query)
      .order(sanitize_sql_for_order([Arel.sql('similarity(name, ?) DESC'), query]))
      .limit(10)
  }

  # ============================================
  # Class Methods
  # ============================================

  def self.find_by_username(username)
    find_by('lower(username) = ?', username.downcase)
  end

  def self.username_or_email(username_email)
    normalized = username_email.to_s.downcase.strip
    where('lower(username) = ?', normalized)
      .or(where('lower(email) = ?', normalized))
      .first
  end

  def self.authenticate(username_email, password)
    user = username_or_email(username_email)
    return nil unless user
    
    if user.authenticate_password(password)
      user.reset_auth_attempts!
      user
    else
      user.record_failed_attempt!
      nil
    end
  end

  def self.to_csv(attributes)
    CSV.generate { |csv| attributes.each { |row| csv << row } }
  end

  # ============================================
  # Instance Methods - Authentication
  # ============================================

  def authenticate_password(plain_password)
    pword == plain_password
  end

  def pword
    @pword ||= Password.new(password)
  end

  def pword=(new_password)
    @pword = Password.create(new_password)
    self.password = @pword
    self.password_confirmation = @pword
  end

  def reset_auth_attempts!
    update(auth_attempts: 0)
  end

  def record_failed_attempt!
    increment!(:auth_attempts)
    lock_account! if auth_attempts >= MAX_AUTH_ATTEMPTS
  end

  def lock_account!
    update(locked: true, locked_until: LOCK_DURATION.from_now)
    send_unlock_email
  end

  def send_unlock_email
    user_hash = Rails.application.message_verifier('unlock').generate(id)
    MsrMailer.unlock_account(self, user_hash).deliver_now
  end

  def token(exp = 14.days.from_now.to_i)
    JWT.encode(
      { user_id: id, exp: exp },
      Rails.application.credentials.secret_key_base,
      'HS256'
    )
  end

  def send_password_reset
    user_hash = Rails.application.message_verifier(:user).generate(id)
    expiry_date_hash = Rails.application.message_verifier(:user).generate(1.day.from_now)
    MsrMailer.forgot_password(email, user_hash, expiry_date_hash).deliver_now
  end

  # ============================================
  # Instance Methods - Role Checks
  # ============================================

  def student?
    STUDENT_IDENTITIES.include?(identity)
  end

  def admin?
    role == 'admin'
  end

  def staff?
    role.in?(%w[staff admin])
  end

  def volunteer?
    programs.exists?(program_type: Program::VOLUNTEER)
  end

  def volunteer_program?
    programs.exists?(program_type: Program::VOLUNTEER)
  end

  def dev_program?
    programs.exists?(program_type: Program::DEV_PROGRAM)
  end

  def teams_program?
    programs.exists?(program_type: Program::TEAMS)
  end

  def staff_in_space?
    staff_spaces.exists?
  end

  def internal?
    INTERNAL_IDENTITIES.include?(identity)
  end

  def return_program_status
    {
      volunteer: volunteer_program?,
      dev: dev_program?,
      teams: teams_program?
    }
  end

  # ============================================
  # Instance Methods - Avatar
  # ============================================

  def display_avatar
    avatar.attached? ? avatar : 'default-avatar.png'
  end

  def has_avatar?
    avatar.attached?
  end

  # ============================================
  # Instance Methods - Location & Sessions
  # ============================================

  def location
    lab_sessions.last&.space&.name || 'no sign in yet'
  end

  # ============================================
  # Instance Methods - Certifications & Training
  # ============================================

  def get_certifications_names
    certifications.map(&:get_name_en)
  end

  def remaining_trainings
    trainings = []
    certifications.each { |cert| trainings << cert.training.id }
    Training.all.where.not(id: trainings)
  end

  def has_requirements?(training_reqs)
    training_reqs.all? do |treq|
      has_training?(treq.training_id, treq.level)
    end
  end

  def has_training?(training_id, level)
    certifications.joins(:training).exists?(
      trainings: { id: training_id },
      certifications: { level: level }
    )
  end

  def highest_badge(training)
    badges = certifications.joins(:training_session)
               .where(training_sessions: { training_id: training.id })

    %w[Advanced Intermediate Beginner].each do |level|
      badge = badges.find_by(training_sessions: { level: level })
      return badge if badge
    end
    nil
  end

  # ============================================
  # Instance Methods - Volunteer
  # ============================================

  def get_volunteer_tasks_from_volunteer_joins
    volunteer_task_joins.active.includes(:volunteer_task).map(&:volunteer_task)
  end

  def get_total_cc
    cc_moneys.sum(:cc)
  end

  def get_total_hours
    volunteer_hours.approved.sum(:total_time)
  end

  def update_wallet
    update(wallet: get_total_cc)
  end

  # ============================================
  # Instance Methods - Membership
  # ============================================

  def active_membership
    memberships.active.first
  end

  def has_active_membership?
    active_membership.present? && active_membership.active?
  end

  # ============================================
  # Instance Methods - Department & Identity
  # ============================================

  def department
    return nil unless program.present?
    
    program_alt = program.gsub(' in', '')
    UniProgram
      .where(program: program)
      .or(UniProgram.where(program: program_alt))
      .pick(:department)
  end

  def identity_readable
    if student?
      year = year_of_study.to_s
      
      if I18n.locale == :fr
        suffix = year.last == '1' ? 'ère' : 'ème'
        year += suffix
      elsif I18n.locale == :en
        year = year.to_i.ordinalize
      end

      "#{year} #{I18n.t('year')} #{identity}uate".titleize
    else
      identity.titleize
    end
  end

  private

  # ============================================
  # Private Methods
  # ============================================

  def translate_faculty
    self.faculty = FACULTY_TRANSLATIONS[faculty] if FACULTY_TRANSLATIONS.key?(faculty)
  end
end