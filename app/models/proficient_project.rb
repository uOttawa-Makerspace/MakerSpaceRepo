class ProficientProject < ActiveRecord::Base
  has_and_belongs_to_many :users
  belongs_to :training
  has_many :photos,       dependent: :destroy
  has_many :repo_files,   dependent: :destroy
  has_many :videos,       dependent: :destroy
end
