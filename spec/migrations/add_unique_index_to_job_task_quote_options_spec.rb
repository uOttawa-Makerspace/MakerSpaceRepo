# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261113130000_add_unique_index_to_job_task_quote_options")

# CREATE INDEX CONCURRENTLY cannot run in a transaction, so this spec runs outside the transactional wrapper.
# It drops the index to build duplicate rows, then restores it and removes its rows.
RSpec.describe AddUniqueIndexToJobTaskQuoteOptions do
  self.use_transactional_tests = false

  let(:conn) { ActiveRecord::Base.connection }
  let(:index) { described_class::INDEX_NAME }
  let!(:job_order) { create(:job_order) }
  let!(:quote) { create(:job_task_quote, job_task: job_order.job_tasks.create!(title: "Task #1")) }
  let!(:option) { create(:job_option) }
  let!(:other_option) { create(:job_option) }

  before { conn.execute("DROP INDEX IF EXISTS #{index}") }

  after do
    JobTaskQuoteOption.where(job_task_quote_id: quote.id).delete_all
    migrate(:up) unless found
    quote.destroy
    job_order.job_tasks.destroy_all
    job_order.destroy
    job_order.user.destroy
    JobOption.where(id: [option.id, other_option.id]).delete_all
  end

  def found = conn.indexes(:job_task_quote_options).find { |i| i.name == index }

  def migrate(direction = :up)
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(direction) }
  end

  def insert(job_option_id: option.id, price: 5)
    JobTaskQuoteOption.insert_all!([{ job_task_quote_id: quote.id, job_option_id: job_option_id, price: price,
                                      created_at: Time.current, updated_at: Time.current }]).rows.flatten.first
  end

  def rows
    conn.select_rows("SELECT id, job_task_quote_id, job_option_id, price FROM job_task_quote_options " \
                     "WHERE job_task_quote_id = #{quote.id} ORDER BY id")
  end

  it "builds a valid unique index that refuses a second row for the quote and option" do
    insert
    migrate

    expect(found).to have_attributes(unique: true, columns: %w[job_task_quote_id job_option_id])
    expect(found).to be_valid
    expect { insert(price: 9) }.to raise_error(ActiveRecord::RecordNotUnique)
    expect { insert(job_option_id: other_option.id) }.not_to raise_error
  end

  it "stops with the duplicate pairs listed and changes no row when duplicates exist" do
    first = insert(price: 5)
    second = insert(price: 7)
    before_rows = rows

    expect { migrate }.to raise_error(
      UniqueIndexGuard::DuplicatesFound,
      /job_task_quote_id=#{quote.id}, job_option_id=#{option.id} -> ids #{first},#{second}/
    )

    expect(found).to be_nil
    expect(rows).to eq(before_rows)
  end

  it "is safe to run twice" do
    insert
    migrate
    expect { migrate }.not_to raise_error
    expect(found).to be_valid
  end

  it "drops only the index on down, keeping every row" do
    insert
    migrate
    before_rows = rows
    migrate(:down)

    expect(found).to be_nil
    expect(rows).to eq(before_rows)
  end
end
