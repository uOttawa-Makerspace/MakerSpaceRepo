class Help
  include ActiveModel::Validations
  include ActiveModel::Conversion
  extend ActiveModel::Naming

  attr_accessor :name, :email, :content, :subject, :comments

  validates :name,
            presence: {
              message: "Veuillez entrer votre nom / You name is required."
            }
  validates :email,
            presence: {
              message:
                "Veuillez entrer votre addresse couriel / An email address is required."
            }
  validates :subject,
            presence: {
              message:
                "Veuillez entrer la ligne d'objet / Please enter the subject line"
            }
  validates :comments,
            presence: {
              message:
                "Veuillez entrer vos commentaires / Please enter a message"
            }

  def initialize(attributes = {})
    attributes.each { |name, value| send("#{name}=", value) }
  end

  def persisted?
    false
  end
end
