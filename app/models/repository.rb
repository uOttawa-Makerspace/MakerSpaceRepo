class Repository < ActiveRecord::Base
  extend FriendlyId
  friendly_id :title, use: [:slugged, :finders]
 
  belongs_to :user
  has_many :photos, dependent: :destroy
  has_many :tags, dependent: :destroy
  has_many :comments, dependent: :destroy
  has_many :likes, dependent: :destroy
  has_many :makes, class_name: "Repository", foreign_key: "make_id"
  belongs_to :parent, class_name: "Repository", foreign_key: "make_id"

  paginates_per 12

  searchable do
    text    :title, :boost => 5.0
    text    :description
    text    :category
    text    :tags do
              tags.map { |tag| tag.name }
            end
    integer :like
    integer :make
    time    :created_at
    time    :updated_at
  end

  def self.category_options
    ["3D-Model", "Wearables", "Mobile", "Internet of Things", 
     "Bio-Medical", "Virtual Reality" ]
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
    format:     { with:    /\A[-a-zA-Z\d\s]*\z/ },
    presence:   { message: "Repository name is required."},
    uniqueness: { message: "Repository name is already in use." }   

  # validates :category,
  #   inclusion: { within: category_options },
  #   presence: { message: "A category is required."}

  # validates :license, 
  #   inclusion: { within: license_options },
  #   presence: { message: "A license is required."}

end
