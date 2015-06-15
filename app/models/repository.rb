class Repository < ActiveRecord::Base
  belongs_to :user

  has_many :photos, dependent: :destroy
  has_many :tags, dependent: :destroy
  has_many :comments, dependent: :destroy
  has_many :likes, dependent: :destroy

  def self.category_options
    ["3D-Model", "Wearables", "Mobile", "Internet of Things", 
     "Bio-Medical", "Virtual Reality" ]
  end

  def self.license_options
    ["Creative Commons - Attribution - Share Alike",
     "Creative Commons - Attribution - No Derivatives",
     "Creative Commons - Attribution - Non-Commercial",
     "Attribution - Non-Commercial - Share Alike",
     "Attribution - Non-Commercial - No Derivatives",
     "Creative Commons - Public Domain Dedication",
     "GNU - GPL", "GNU - LGPL", "BSD License" ]
  end

  validates :title, 
    presence: { message: "Repository name is required."},
    uniqueness: { message: "Repository name is already in use." }   

  validates :category,
    inclusion: { within: category_options },
    presence: { message: "A category is required."}

  validates :license, 
    inclusion: { within: license_options },
    presence: { message: "A license is required."}

end
