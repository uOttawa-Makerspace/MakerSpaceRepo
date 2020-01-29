class Program < ActiveRecord::Base
  belongs_to :user
  validates :user,
            presence: { message: "A user is required." },
            uniqueness: { scope: :program_type, message: "An user can only join a program once" }
  validates :program_type, presence: { message: "The type of the program is required. Either 'Volunteer Program' or 'Development Program'" }
end
