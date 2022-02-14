class RemoveNullConstraintFromJobServices < ActiveRecord::Migration[6.1]
  def change
    change_column_null :job_services, :unit, true
    change_column_null :job_services, :internal_price, true
    change_column_null :job_services, :external_price, true
  end
end
