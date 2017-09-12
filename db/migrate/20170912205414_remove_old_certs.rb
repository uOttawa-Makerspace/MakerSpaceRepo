class RemoveOldCerts < ActiveRecord::Migration
  def up
    Certification.where(training_session_id: nil).destroy_all
  end
end
