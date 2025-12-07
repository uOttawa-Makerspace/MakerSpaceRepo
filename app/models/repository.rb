# frozen_string_literal: true

class Repository < ApplicationRecord
  include BCrypt
  require "bcrypt"

  has_and_belongs_to_many :users
  belongs_to :project_proposal, optional: true
  has_many :photos, dependent: :destroy
  # https://api.rubyonrails.org/classes/ActiveRecord/NestedAttributes/ClassMethods.html
  # This method requires us to mark photos for deletion.
  # TODO: Move the attachments into a concern?
  accepts_nested_attributes_for :photos, allow_destroy: true
  has_many :repo_files, dependent: :destroy
  has_many :categories, dependent: :destroy
  has_many :equipments, dependent: :destroy
  has_many :comments, dependent: :destroy
  has_many :likes, dependent: :destroy
  has_many :makes, class_name: "Repository", foreign_key: "make_id"
  belongs_to :parent,
             class_name: "Repository",
             foreign_key: "make_id",
             optional: true
  paginates_per 12

  scope :public_repos, -> { where(share_type: "public") }

  def self.license_options
    [
      "Creative Commons - Attribution",
      "Creative Commons - Attribution - Share Alike",
      "Creative Commons - Attribution - No Derivatives",
      "Creative Commons - Attribution - Non-Commercial",
      "Attribution - Non-Commercial - Share Alike",
      "Attribution - Non-Commercial - No Derivatives"
    ]
  end

  validates :title,
            presence: {
              message: "Project title is required."
            },
            uniqueness: {
              message: "Project title is already in use.",
              scope: :user_username
            }

  validates :share_type, inclusion: { in: %w[public private], message: "" }

  validates :password,
            presence: {
              message: "Password is required for private projects"
            },
            if: :private?

  # validates :category,
  #           inclusion: { within: CategoryOption.show_options },
  #           presence: { message: "A category is required."},
  #           length: {maximum: 5, message:"You may only select 5 categories."}
  default_scope { where(deleted: false) }

  before_save do
    self.youtube_link = nil if youtube_link && !YoutubeID.from(youtube_link)
  end

  before_create do
    self.slug = title.downcase.gsub(/[^0-9a-z ]/i, "").gsub(/\s+/, "-")
  end

  before_update do
    self.slug =
      id.to_s + "." + title.downcase.gsub(/[^0-9a-z ]/i, "").gsub(/\s+/, "-")
  end

  before_destroy { users.each { |u| u.decrement!(:reputation, 25) } }

  def private?
    share_type.eql?("private")
  end

  def self.authenticate(id, password)
    @repository = Repository.find(id)
    @repository.pword == password
  end

  def pword
    @pword ||= Password.new(password)
  end

  def pword=(new_password)
    pass = BCrypt::Password.create(new_password)
    self.password = pass
  end

  def self.to_csv(attributes)
    CSV.generate { |csv| attributes.each { |row| csv << row } }
  end

  scope :between_dates_picked,
        ->(start_date, end_date) {
          where("created_at BETWEEN ? AND ? ", start_date, end_date)
        }

  # validates :license,
  #   inclusion: { within: license_options },
  #   presence: { message: "A license is required."}
end
