require "rails_helper"
require Rails.root.join("db/migrate/20261104150100_add_date_of_task_check_to_volunteer_hours")

RSpec.describe AddDateOfTaskCheckToVolunteerHours do
  let(:connection) { ActiveRecord::Base.connection }
  let(:name) { described_class::CHECK_NAME }
  let(:user) { create(:user, :volunteer_with_volunteer_program) }
  let(:task) { create(:volunteer_task) }

  def migrate(direction = :up)
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(direction) }
  end

  def insert_hour(date)
    VolunteerHour.new(user: user, volunteer_task: task, date_of_task: date).save!(validate: false)
  end

  it "makes the database refuse a new hour without a date" do
    expect(connection.check_constraints(:volunteer_hours).map(&:name)).to include(name)
    expect { insert_hour(nil) }.to raise_error(ActiveRecord::StatementInvalid, /#{name}/)
    expect { insert_hour(Time.current) }.to change(VolunteerHour, :count).by(1)
  end

  it "is added NOT VALID, so blank rows already in the table do not stop it" do
    migrate(:down)
    insert_hour(nil)

    migrate

    expect(connection.check_constraints(:volunteer_hours).find { |c| c.name == name }.validate?).to be(false)
    expect { insert_hour(nil) }.to raise_error(ActiveRecord::StatementInvalid, /#{name}/)
  end

  it "can be run again and removed on down" do
    migrate
    expect(connection.check_constraints(:volunteer_hours).count { |c| c.name == name }).to eq(1)
    migrate(:down)
    expect(connection.check_constraints(:volunteer_hours).map(&:name)).not_to include(name)
  end
end
