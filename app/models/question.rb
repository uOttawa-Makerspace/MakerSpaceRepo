class Question < ActiveRecord::Base
  belongs_to :user
  has_many :answers
  accepts_nested_attributes_for :answers

  CATEGORIES = ["Basic Training",
                "Mill Training",
                "Lathe Training",
                "MIG Training",
                "TIG Training",
                "General Satefy",
                "Basic 3D Printing",
                "Advanced 3D Printing",
                "Basic Laser Cutting",
                "Advanced Laser Cutting",
                "Basic Arduino",
                "Advanced Arduino",
                "Embroidery",
                "CAD modeling",
                "3D Scanning",
                "Virtual Reality",
                "Soldering"]
end
