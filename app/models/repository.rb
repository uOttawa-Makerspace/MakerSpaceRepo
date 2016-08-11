class Repository < ActiveRecord::Base
  belongs_to :user
  has_many   :photos,   dependent: :destroy
  has_many   :repo_files,   dependent: :destroy
  has_many   :categories,     dependent: :destroy
  has_many   :equipments,     dependent: :destroy
  has_many   :comments, dependent: :destroy
  has_many   :likes,    dependent: :destroy
  has_many   :makes,    class_name: "Repository", foreign_key: "make_id"
  belongs_to :parent,   class_name: "Repository", foreign_key: "make_id"

  paginates_per 12

  searchable do
    text    :title, :boost => 5.0
    text    :description
    text    :categories do
              categories.map { |category| category.name }
            end
    text    :equipments do
              equipments.map { |equipment| equipment.name }
            end
    integer :like
    integer :make
    time    :created_at
    time    :updated_at
  end

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

  before_save do 
    self.slug = self.title.downcase.gsub(/[^0-9a-z ]/i, '').gsub(/\s+/, '-')
  end 

  before_destroy do
    self.user.decrement!(:reputation, 25)
  end

  # validates :category,
  #   inclusion: { within: category_options },
  #   presence: { message: "A category is required."}

  # validates :license, 
  #   inclusion: { within: license_options },
  #   presence: { message: "A license is required."}

end
