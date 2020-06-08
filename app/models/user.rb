class User < ActiveRecord::Base
  include BCrypt
  include ActiveModel::Serialization

  has_one :rfid, dependent: :destroy
  has_many :upvotes, dependent: :destroy
  has_many :comments, dependent: :destroy
  has_and_belongs_to_many :repositories, dependent: :destroy
  has_many :certifications, dependent: :destroy
  has_many :lab_sessions, dependent: :destroy
  has_and_belongs_to_many :training_sessions
  accepts_nested_attributes_for :repositories
  has_many :project_proposals
  has_many :project_joins, dependent: :destroy
  has_many :printer_sessions, dependent: :destroy
  has_many :volunteer_hours
  has_many :volunteer_tasks
  has_one :skill
  has_one :volunteer_request, dependent: :destroy
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
  has_many :orders, dependent: :destroy
  has_many :order_items, through: :orders
  has_many :discount_codes, dependent: :destroy

  validates :name,
            presence: true,
            length: {maximum: 50}

  validates :username,
            presence: true,
            uniqueness: true,
            format: {with: /\A[a-zA-Z\d]*\z/},
            length: {maximum: 20}

  validates :email,
            presence: true,
            uniqueness: true

  validates :how_heard_about_us,
            length: {maximum: 250}

  validates :read_and_accepted_waiver_form,
            inclusion: {in: [true]}, on: :create

  validates :password,
            presence: true,
            confirmation: true,
            format: {with: /(?=.*[0-9])(?=.*[a-z])(?=.*[A-Z]).{8,}/}

  validates :gender,
            presence: true,
            inclusion: {in: ["Male", "Female", "Other", "Prefer not to specify", "unknown"]}

  validates :faculty,
            presence: true, if: :student?

  validates :program,
            presence: true, if: :student?

  validates :year_of_study,
            presence: true, if: :student?

  validates :student_id,
            presence: true, if: :student?

  validates :identity,
            presence: true,
            inclusion: {in: ['grad', 'undergrad', 'faculty_member', 'community_member', 'unknown']}

  has_attached_file :avatar, :default_url => "default-avatar.png"
  validates_attachment_content_type :avatar, :content_type => /\Aimage\/.*\Z/

  scope :no_waiver_users, -> { where('read_and_accepted_waiver_form = false') }
  scope :between_dates_picked, ->(start_date, end_date) { where('created_at BETWEEN ? AND ? ', start_date, end_date) }
  scope :frequency_between_dates, -> (start_date, end_date) { joins(:lab_sessions => :space).where("lab_sessions.sign_in_time BETWEEN ? AND ? AND spaces.name = ?", start_date, end_date, "Makerspace") }
  scope :active, -> { where(:active => true) }
  scope :unknown_identity, -> { where(identity: "unknown") }

  def self.authenticate(username_email, password)
    user = User.username_or_email(username_email)
    user if user && user.pword == password
  end

  def self.username_or_email(username_email)
    a = self.arel_table
    self.where(a[:username].eq(username_email).or(a[:email].eq(username_email))).first
  end

  def pword
    @pword ||= Password.new(password)
  end

  def pword=(new_password)
    @pword = Password.create(new_password)
    self.password = @pword
    self.password_confirmation = @pword
  end

  def student?
    self.identity == "grad" || self.identity == "undergrad"
  end

  def admin?
    self.role.eql?("admin")
  end

  def staff?
    self.role.eql?("staff") || self.role.eql?("admin")
  end

  def volunteer?
    self.role.eql?("volunteer")
  end

  def volunteer_program?
    self.programs.pluck(:program_type).include?(Program::VOLUNTEER)
  end

  def dev_program?
    self.programs.pluck(:program_type).include?(Program::DEV_PROGRAM)
  end


  def self.to_csv(attributes)
    CSV.generate do |csv|
      attributes.each do |row|
        csv << row
      end
    end
  end

  def location
    if self.lab_sessions.last.equal? nil
      return 'no sign in yet'
    end
    return self.lab_sessions.last.space.name
  end

  def get_certifications_names
    cert = []
    self.certifications.each do |c|
      cert << c.training.name
    end
    return cert
  end

  def get_volunteer_tasks_from_volunteer_joins
    volunteer_tasks = []
    vtjs = self.volunteer_task_joins.active
    vtjs.each do |vtj|
      volunteer_tasks << vtj.volunteer_task
    end
    return volunteer_tasks
  end

  def get_total_cc
    self.cc_moneys.sum(:cc)
  end

  def get_total_hours
    self.volunteer_hours.approved.sum(:total_time)
  end

  def get_badges(training_id)
    training_ids = []
    self.certifications.each do |cert|
      training_ids << cert.training_session.training.id
    end
    if training_ids.include?(training_id)
      path = "badges/bronze.png"
    else
      path = "badges/none.png"
    end
    return path
  end

  def remaining_trainings
    trainings = []
    self.certifications.each do |cert|
      trainings << cert.training.id
    end
    return Training.all.where.not(id: trainings)
  end

  def return_program_status
    certifications = self.get_certifications_names
    if !(certifications.include?("3D Printing") && certifications.include?("Basic Training"))
      status = 0
    elsif !(self.volunteer? || self.volunteer_program?) && !self.dev_program?
      status = 1
    elsif (self.volunteer? || self.volunteer_program?) && !self.dev_program?
      status = 2
    elsif !(self.volunteer? || self.volunteer_program?) && self.dev_program?
      status = 3
    elsif (self.volunteer? || self.volunteer_program?) && self.dev_program?
      status = 4
    end
    return status
  end

  def update_wallet
    self.update_attributes(wallet: self.get_total_cc)
  end

  def has_required_badges?(badge_requirements)
      user_badges_set = self.badges.pluck(:badge_template_id).to_set
      badge_requirements_set = badge_requirements.pluck(:badge_template_id).to_set
      badge_requirements_set.subset?(user_badges_set)
  end

end
