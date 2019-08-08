class Question < ActiveRecord::Base
  belongs_to :user
  has_many :exam_questions
  has_many :exams, through: :exam_questions
  has_many :answers,  dependent: :destroy

  has_many :exam_responses, through: :exam_questions do
    def find_by_user(user)
      joins(:exam).where("exams.user_id": user.id)
    end
  end

  def response_for_exam(exam)
    exam_responses.joins(:exam).find_by("exams.id": exam.id)
  end

  accepts_nested_attributes_for :answers
  has_attached_file :image, styles: { medium: "300x300>", thumb: "100x100>" }
  validates_attachment_content_type :image, content_type: /\Aimage\/.*\z/

  CATEGORIES = (Training.all_training_names << "General Satefy").sort

  # TODO: Clean this when finished

  # CATEGORIES = ["Basic Training",
  #               "Mill Training",
  #               "Lathe Training",
  #               "MIG Training",
  #               "TIG Training",
  #               "General Satefy",
  #               "Basic 3D Printing",
  #               "Advanced 3D Printing",
  #               "Basic Laser Cutting",
  #               "Advanced Laser Cutting",
  #               "Basic Arduino",
  #               "Advanced Arduino",
  #               "Embroidery",
  #               "CAD modeling",
  #               "3D Scanning",
  #               "Virtual Reality",
  #               "Soldering"]

  # ["3D Printing Basics",
  #  "3D scanning",
  #  "Advanced 3D Printing",
  #  "Arduino Basics",
  #  "Basic Lathe Training",
  #  "Basic Mill Training",
  #  "Basic TIG ",
  #  "Basic Training",
  #  "Embroidery",
  #  "GNG 3D Printing training",
  #  "GNG 3D printing training",
  #  "GNG Laser training",
  #  "GNG laser training",
  #  "Laser Cutting Basics",
  #  "MCG Basic Lathe Training",
  #  "MCG Basic Mill Training ",
  #  "Makerspace Volunteer",
  #  "Mig Welding Training",
  #  "PCB Design",
  #  "Soldeing Basics",
  #  "Tig Welding Training",
  #  "Welding Safety and Basic MIG"]
end
