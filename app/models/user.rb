class User < ActiveRecord::Base
  include BCrypt
  include ActiveModel::Serialization

  has_one  :rfid,         dependent: :destroy
  has_many :upvotes,      dependent: :destroy
  has_many :comments,     dependent: :destroy
  has_and_belongs_to_many :repositories, dependent: :destroy
  has_many :certifications, dependent: :destroy
  has_many :lab_sessions, dependent: :destroy
  has_and_belongs_to_many :training_sessions
  accepts_nested_attributes_for :repositories
  has_many :project_proposals
  has_many :project_joins,     dependent: :destroy
  has_many :printer_sessions,     dependent: :destroy
  has_many :volunteer_hours
  has_many :volunteer_tasks
  has_one :skill
  has_many :volunteer_task_joins
  has_many :training_sessions

  validates :name,
    presence: true,
    length: { maximum: 50 }

  validates :username,
    presence: true,
    uniqueness: true,
    format: { with: /\A[a-zA-Z\d]*\z/ },
    length: { maximum: 20 }

  validates :email,
    presence: true,
    uniqueness: true

  validates :how_heard_about_us,
    length: { maximum: 250 }

  validates :read_and_accepted_waiver_form,
    inclusion: { in: [true] }, on: :create

  validates :password,
    presence: true,
    confirmation: true,
    format: { with: /(?=.*[0-9])(?=.*[a-z])(?=.*[A-Z]).{8,}/ }

  validates :gender,
    presence: true,
    inclusion: { in: ["Male", "Female", "Other", "Prefer not to specify", "unknown"] }

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
    inclusion: { in: ['grad', 'undergrad', 'faculty_member', 'community_member', 'unknown'] }

  has_attached_file :avatar, :default_url => "default-avatar.png"
  validates_attachment_content_type :avatar, :content_type => /\Aimage\/.*\Z/

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

  scope :unknown_identity, -> { where(identity:"unknown") }


  def admin?
    self.role.eql?("admin")
  end

  def staff?
    self.role.eql?("staff") || self.role.eql?("admin")
  end

  def volunteer?
    self.role.eql?("volunteer")
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

  scope :no_waiver_users, -> { where('read_and_accepted_waiver_form = false') }

  scope :between_dates_picked, ->(start_date , end_date){ where('created_at BETWEEN ? AND ? ', start_date , end_date) }

  scope :frequency_between_dates, -> (start_date, end_date){joins(:lab_sessions => :space).where("lab_sessions.sign_in_time BETWEEN ? AND ? AND spaces.name = ?", start_date, end_date, "Makerspace")}

  scope :active, -> {where(:active => true)}

end
