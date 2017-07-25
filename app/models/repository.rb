class Repository < ActiveRecord::Base
  include BCrypt

  belongs_to :user
  has_many   :users
  has_many   :photos,   dependent: :destroy
  has_many   :repo_files,   dependent: :destroy
  has_many   :categories,     dependent: :destroy
  has_many   :equipments,     dependent: :destroy
  has_many   :comments, dependent: :destroy
  has_many   :likes,    dependent: :destroy
  has_many   :makes,    class_name: "Repository", foreign_key: "make_id"
  belongs_to :parent,   class_name: "Repository", foreign_key: "make_id"
  paginates_per 12

  def self.license_options
    ["Creative Commons - Attribution",
     "Creative Commons - Attribution - Share Alike",
     "Creative Commons - Attribution - No Derivatives",
     "Creative Commons - Attribution - Non-Commercial",
     "Attribution - Non-Commercial - Share Alike",
     "Attribution - Non-Commercial - No Derivatives"]
  end


  validates :title,
    format:     { with:    /\A[-a-zA-Z\d\s]*\z/, message: "Invalid project title" },
    presence:   { message: "Project title is required."},
    uniqueness: { message: "Project title is already in use.", scope: :user_username}

  validates :share_type,
    presence: { message: "Is your project public or private?" }

  validates :password,
    presence: { message: "Password is required for private projects" }, if: :private?

  before_save do
    self.slug = self.title.downcase.gsub(/[^0-9a-z ]/i, '').gsub(/\s+/, '-')
  end

  before_destroy do
    self.user.decrement!(:reputation, 25)
  end

  def private?
    self.share_type.eql?("private")
  end

  def self.authenticate(slug, password)
    @repository = Repository.find_by_slug(slug)
    return @repository.pword == password
  end

  def pword
    @pword ||= Password.new(password)
  end

  # validates :category,
  #   inclusion: { within: category_options },
  #   presence: { message: "A category is required."}

  # validates :license,
  #   inclusion: { within: license_options },
  #   presence: { message: "A license is required."}

end
