class Question < ActiveRecord::Base
  belongs_to :user
  has_many :answers,  dependent: :destroy
  has_many :exam_questions
  has_many :question_responses
  accepts_nested_attributes_for :answers
  has_attached_file :image, styles: { medium: "300x300>", thumb: "100x100>" }
  validates_attachment_content_type :image, content_type: /\Aimage\/.*\z/

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
