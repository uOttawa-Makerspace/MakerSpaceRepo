class User < ActiveRecord::Base
  include BCrypt
  include ActiveModel::Serialization
  
  has_many :upvotes
  has_many :comments
  has_many :repositories, dependent: :destroy
    accepts_nested_attributes_for :repositories
  has_many :makes, dependent: :destroy

  validates :first_name, 
    presence: { message: "First name is required."}

  validates :last_name, 
    presence: { message: "Last name is required."}

  validates :username,
    presence: { message: "Username is required." },
    uniqueness: { message: "Username is already in use." }   

  validates :email, 
    presence: { message: "Email is required." },
    uniqueness: { message: "Email is already in use." }

  validates :password, 
    presence: { message: "Password is required." },
    confirmation: {message: "Passwords do not match."},
    # format: {with: /(?=.*[a-z])(?=.*[A-Z])(?=.*[0-9])(?=.*[\W]).{8,}/,
    format: {with: /(?=.*[a-z])(?=.*[A-Z])(?=.*[0-9]).{8,}/,
             message: "Passwords must have one lowercase letter, one uppercase letter and be 8 characters long."},
    on: :create

  validates :password_confirmation, 
    presence: { message: "Password confirmation is required." },
    on: :create

  has_attached_file :avatar, :default_url => "default-avatar.png"
  validates_attachment_content_type :avatar, :content_type => /\Aimage\/.*\Z/


  def self.authenticate(username_email, password)
    a = self.arel_table
    user = self.where(a[:username].eq(username_email)
      .or(a[:email].eq(username_email))).first
    user if user && user.pword == password
  end

  def pword
    @pword ||= Password.new(password)
  end

  def pword=(new_password)
    @pword = Password.create(new_password)
    self.password = @pword
    self.password_confirmation = @pword
  end

end
