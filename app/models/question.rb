class Question < ActiveRecord::Base
  belongs_to :user
  has_many :exam_questions
  has_many :exams, through: :exam_questions
  # has_many :exam_responses #, through :exam_questions
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

  # has_many :question_responses, through: :exam_questions do
  #   def find_by_user(user)
  #     joins(:exam).where("exams.user_id": user.id)
  #   end
  # end
  #
  # def response_for_exam(exam)
  #   question_responses.joins(:exam).find_by("exams.id": exam.id)
  # end

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
