class User < ActiveRecord::Base
  include BCrypt
  include ActiveModel::Serialization

  has_one  :rfid,         dependent: :destroy
  has_many :upvotes,      dependent: :destroy
  has_many :comments,     dependent: :destroy
  has_many :repositories, dependent: :destroy
  has_many :certifications, dependent: :destroy
  has_many :lab_sessions, dependent: :destroy
  has_and_belongs_to_many :training_sessions
  accepts_nested_attributes_for :repositories
  has_many :project_proposals
  has_many :project_joins,     dependent: :destroy
  has_many :printer_sessions,     dependent: :destroy

  validates :name,
    presence: { message: "Your name is required." },
    length: { maximum: 50, message: 'Your name must be less than 50 characters.' }

  validates :username,
    presence: { message: "Your username is required." },
    uniqueness: { message: "Your username is already in use." },
    format:     { with:    /\A[a-zA-Z\d]*\z/, message: "Your username may only contain alphanumeric characters" },
    length: { maximum: 20, message: 'Your username must be less than 20 characters.' }

  validates :email,
    presence: { message: "Your email is required." },
    uniqueness: { message: "Your email is already in use." }

  validates :description,
    length: { maximum: 250, message: 'Maximum of 250 characters.' }

  validates :read_and_accepted_waiver_form,
    inclusion: {in: [true], on: :create, message: 'You must agree to the waiver of form' }

  validates :password,
    presence: { message: "Your password is required." },
    confirmation: {message: "Your passwords do not match."},
    format: {with: /(?=.*[0-9])(?=.*[a-z])(?=.*[A-Z]).{8,}/,
             message: "Your passwords must have one lowercase letter, one uppercase letter, one number and be eight characters long."}


  validates :gender,
    presence: {message: "Your gender is required."},
    inclusion: {in:["Male", "Female", "Other", "Prefer not to specify", "unknown"]}

  validates :faculty,
    presence: {message: "Please provide your faculty"}, if: :student?

  validates :program,
    presence: {message: "Please provide your program"}, if: :student?

  validates :year_of_study,
    presence: {message: "Please provide your year of study"}, if: :student?

  validates :student_id,
    presence: {message: "Please provide your student Number"}, if: :student?

  validates :identity,
    presence: {message: "Please identify who you are"},
    inclusion: {in:['grad', 'undergrad', 'faculty_member', 'community_member', 'unknown']}

  has_attached_file :avatar, :default_url => "default-avatar.png"
  validates_attachment_content_type :avatar, :content_type => /\Aimage\/.*\Z/


  def self.authenticate(username_email, password)
    user = User.username_or_email(username_email)
    user if user && user.pword == password
  end

  def self.username_or_email(username_email)
    a = self.arel_table
    user = self.where(a[:username].eq(username_email).or(a[:email].eq(username_email))).first
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
    self.identity.eql?("grad") || self.identity.eql?("undergrad")
  end

  scope :unknown_identity, -> { where(identity:"unknown") }


  def admin?
    self.role.eql?("admin")
  end

  def staff?
    self.role.eql?("staff") || self.role.eql?("admin")
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

end
