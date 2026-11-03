# frozen_string_literal: true

require "rails_helper"
%w[
  20261103000002_restore_job_task_quote_quantities
  20261103000003_restore_missing_job_order_services_as_tasks
  20261103000004_attach_option_files_to_job_task_options
  20261103000005_import_print_orders_as_job_orders
].each { |name| require Rails.root.join("db/migrate/#{name}") }

# Legacy rows (the old quote tables, the old join table, print orders) are inserted directly:
# the models that wrote them are gone or no longer allow those shapes.
RSpec.describe "job order history repairs" do
  COPY_TIME = Time.utc(2025, 8, 11, 16, 2, 30)

  def table(name) = Class.new(ApplicationRecord) { self.table_name = name }

  def insert(name, attrs)
    now = Time.current
    klass = table(name)
    stamps = %w[created_at updated_at].select { |c| klass.column_names.include?(c) }.index_with { now }
    klass.insert_all!([stamps.merge(attrs)])
    klass.column_names.include?("id") ? klass.order(:id).last : nil
  end

  def run(migration)
    ActiveRecord::Migration.suppress_messages { migration.new.up }
  end

  def blob(name)
    ActiveStorage::Blob.create_before_direct_upload!(
      filename: name, byte_size: 1, checksum: SecureRandom.hex(8), content_type: "application/pdf"
    )
  end

  def attach(type, id, name, blob)
    ActiveStorage::Attachment.insert_all!([{ record_type: type, record_id: id, name: name, blob_id: blob.id, created_at: Time.current }])
  end

  def attachments(type, id) = ActiveStorage::Attachment.where(record_type: type, record_id: id).order(:id)

  let(:user) { create(:user, :regular_user) }
  let(:staff) { create(:user, :admin) }
  let(:job_type) { JobType.find_by(name: "3D Print") || create(:job_type, name: "3D Print") }
  let(:group) { create(:job_service_group, job_type: job_type) }
  let(:service_a) { create(:job_service, job_service_group: group) }
  let(:service_b) { create(:job_service, job_service_group: group) }

  # An order as the multi-task migration left it: one "Main Task", its quote from the old quote's first service.
  def legacy_order(services:, quote_services:, copied_quantity: nil, updated_at: nil, task_service: :first)
    quote = insert("job_order_quotes", service_fee: 10)
    quote_services.each do |service, per_unit, quantity|
      insert("job_order_quote_services", job_order_quote_id: quote.id, job_service_id: service.id, per_unit: per_unit, quantity: quantity)
    end
    order = JobOrder.create!(user: user, job_type: job_type, job_order_quote_id: quote.id)
    services.each { |s| insert("job_orders_services", job_order_id: order.id, job_service_id: s.id) }
    task = JobTask.create!(job_order: order, job_type: job_type, job_service: (task_service == :first ? services.first : task_service), title: "Main Task")
    first = quote_services.first
    q = JobTaskQuote.create!(job_task: task, price: 10, service_price: first[1], service_quantity: copied_quantity || first[2].truncate)
    order.update_columns(created_at: COPY_TIME - 1.year, updated_at: COPY_TIME - 1.year)
    task.update_columns(created_at: COPY_TIME, updated_at: COPY_TIME)
    q.update_columns(created_at: COPY_TIME, updated_at: updated_at || COPY_TIME)
    [order, task, q]
  end

  describe RestoreJobTaskQuoteQuantities do
    it "restores the fraction a never-edited quote lost" do
      _order, _task, q = legacy_order(services: [service_a], quote_services: [[service_a, 0.53, 60.5]])
      run(described_class)
      expect(q.reload.service_quantity).to eq(60.5)
      expect(q.service_price).to eq(0.53)
    end

    it "corrects a quote copied from a service other than its task's" do
      _order, _task, q = legacy_order(services: [service_b, service_a], quote_services: [[service_a, 0.14, 52.25], [service_b, 0, 0]])
      run(described_class)
      expect(q.reload.service_quantity).to eq(0)
      expect(q.service_price).to eq(0)
    end

    it "leaves a quote that was edited after the copy" do
      _order, _task, q = legacy_order(services: [service_a], quote_services: [[service_a, 0.53, 60.5]], updated_at: 1.day.from_now)
      run(described_class)
      expect(q.reload.service_quantity).to eq(60)
    end

    it "leaves a quote whose values are not what the copy produced" do
      _order, _task, q = legacy_order(services: [service_a], quote_services: [[service_a, 0.53, 60.5]], copied_quantity: 7)
      run(described_class)
      expect(q.reload.service_quantity).to eq(7)
    end

    it "also repairs a copy that rounded the quantity" do
      _order, _task, q = legacy_order(services: [service_a], quote_services: [[service_a, 0.53, 60.75]], copied_quantity: 61)
      run(described_class)
      expect(q.reload.service_quantity).to eq(60.75)
    end

    it "takes the lowest-id quote service when the quote lists the task's service twice" do
      _order, _task, q = legacy_order(services: [service_a], quote_services: [[service_a, 0.53, 60.5], [service_a, 0.53, 9.5]])
      run(described_class)
      expect(q.reload.service_quantity).to eq(60.5)
    end

    it "repairs a task with no service from the quote's first service when the copy shape matches" do
      _order, _task, q = legacy_order(services: [service_a], quote_services: [[service_a, 0.53, 60.5]], task_service: nil)
      run(described_class)
      expect(q.reload.service_quantity).to eq(60.5)
    end

    it "repairs a task whose service the quote does not list from the quote's first service" do
      _order, _task, q = legacy_order(services: [service_a], quote_services: [[service_a, 0.53, 60.5]], task_service: service_b)
      run(described_class)
      expect(q.reload.service_quantity).to eq(60.5)
    end

    it "is idempotent" do
      legacy_order(services: [service_a], quote_services: [[service_a, 0.53, 60.5]])
      run(described_class)
      expect { run(described_class) }.not_to(change { JobTaskQuote.pluck(:id, :service_quantity, :service_price, :updated_at) })
    end

    it "is irreversible" do
      expect { described_class.new.down }.to raise_error(ActiveRecord::IrreversibleMigration)
    end
  end

  describe RestoreMissingJobOrderServicesAsTasks do
    # The quantities are restored first, as in the deploy: the migration checks the totals.
    def restore
      run(RestoreJobTaskQuoteQuantities)
      run(described_class)
    end

    it "adds a task per missing service, priced from the old quote service, and the total matches the old one" do
      order, task, = legacy_order(services: [service_a, service_b], quote_services: [[service_a, 2, 3], [service_b, 4, 2.5]])
      restore
      added = order.job_tasks.where.not(id: task.id).sole
      expect(added).to have_attributes(job_service_id: service_b.id, job_type_id: job_type.id, title: "Task #2")
      expect(added.job_task_quote).to have_attributes(price: 0, service_price: 4, service_quantity: 2.5)
      expect(order.reload.total_price).to eq(10 + 2 * 3 + 4 * 2.5)
    end

    it "adds a task without a quote for an order that had no old quote" do
      order = JobOrder.create!(user: user, job_type: job_type)
      insert("job_orders_services", job_order_id: order.id, job_service_id: service_a.id)
      insert("job_orders_services", job_order_id: order.id, job_service_id: service_b.id)
      main = JobTask.create!(job_order: order, job_type: job_type, job_service: service_a, title: "Main Task")
      order.update_columns(created_at: COPY_TIME - 1.year)
      main.update_columns(created_at: COPY_TIME)
      restore
      added = order.job_tasks.find_by!(job_service_id: service_b.id)
      expect(added.job_task_quote).to be_nil
    end

    it "is idempotent" do
      legacy_order(services: [service_a, service_b], quote_services: [[service_a, 2, 3], [service_b, 4, 2.5]])
      restore
      expect { restore }.not_to(change { [JobTask.count, JobTaskQuote.count] })
    end

    it "adds one task and at most one quote when the service is listed twice" do
      order, task, = legacy_order(services: [service_a, service_b, service_b],
                                  quote_services: [[service_a, 2, 3], [service_b, 4, 2.5], [service_b, 0, 0]])
      restore
      added = order.job_tasks.where.not(id: task.id)
      expect(added.count).to eq(1)
      expect(JobTaskQuote.where(job_task_id: added.ids).pluck(:service_price)).to eq([4])
    end

    it "leaves an order that has more than its Main Task" do
      order, = legacy_order(services: [service_a, service_b], quote_services: [[service_a, 2, 3], [service_b, 0, 0]])
      JobTask.create!(job_order: order, job_type: job_type, title: "Task #2")
      # (a task on the second service keeps the totals equal)
      expect { restore }.not_to(change { JobTask.count })
    end

    it "leaves an order created after the multi-task migration" do
      order, task, = legacy_order(services: [service_a, service_b], quote_services: [[service_a, 2, 3], [service_b, 0, 0]])
      order.update_columns(created_at: task.created_at + 1.day)
      expect { restore }.not_to(change { JobTask.count })
    end
    it "skips an order whose Main Task quote was edited since the copy" do
      order, _task, q = legacy_order(services: [service_a, service_b], quote_services: [[service_a, 2, 3], [service_b, 0, 0]],
                                     updated_at: COPY_TIME + 1.day)
      expect { restore }.not_to(change { JobTask.count })
      expect(q.reload.updated_at).to eq(COPY_TIME + 1.day)
      expect(order.job_tasks.count).to eq(1)
    end

    it "raises, naming the orders and adding nothing, when an unedited in-scope order's total differs from its old quote" do
      order, _task, q = legacy_order(services: [service_a, service_b], quote_services: [[service_a, 2, 3], [service_b, 4, 2.5]])
      q.update_columns(price: 999)
      expect { ApplicationRecord.transaction(requires_new: true) { restore } }
        .to raise_error(ActiveRecord::StatementInvalid, /1 old-quote orders do not total.*#{order.id}/m)
      expect(order.job_tasks.count).to eq(1)
    end

    it "only reports, and does not raise, for a differing order outside the scope (quote edited since the copy)" do
      order, _task, q = legacy_order(services: [service_a, service_b], quote_services: [[service_a, 2, 3], [service_b, 4, 2.5]])
      q.update_columns(price: 999, updated_at: COPY_TIME + 1.day)
      expect { restore }.not_to raise_error
      expect(order.job_tasks.count).to eq(1)
    end

    it "only reports a differing old-quote order that has more than its Main Task" do
      order, = legacy_order(services: [service_a, service_b], quote_services: [[service_a, 2, 3], [service_b, 4, 2.5]])
      JobTask.create!(job_order: order, job_type: job_type, title: "Task #2")
      expect { restore }.not_to raise_error
    end

    it "treats a NULL service fee as 0 in the old total" do
      ActiveRecord::Base.connection.execute("ALTER TABLE job_order_quotes ALTER COLUMN service_fee DROP NOT NULL")
      order, _task, q = legacy_order(services: [service_a], quote_services: [[service_a, 2, 3]])
      ActiveRecord::Base.connection.execute("UPDATE job_order_quotes SET service_fee = NULL WHERE id = #{order.job_order_quote_id}")
      q.update_columns(price: 0)
      expect { restore }.not_to raise_error
      q.update_columns(price: 999)
      expect { ApplicationRecord.transaction(requires_new: true) { restore } }
        .to raise_error(ActiveRecord::StatementInvalid, /do not total.*#{order.id}/m)
    end

    it "passes when every old-quote order totals the same as before" do
      legacy_order(services: [service_a, service_b], quote_services: [[service_a, 2, 3], [service_b, 4, 2.5]])
      expect { restore }.not_to raise_error
    end
  end

  describe AttachOptionFilesToJobTaskOptions do
    let(:option) { create(:job_option) }
    let(:order) { JobOrder.create!(user: user, job_type: job_type) }
    let!(:task) { JobTask.create!(job_order: order, job_type: job_type, title: "Main Task") }
    let!(:task_option) { JobTaskOption.create!(job_task: task, job_option: option) }
    let(:file) { blob("opt.pdf") }

    it "attaches the old option's file to the matching task option on the same blob" do
      old = insert("job_order_options", job_order_id: order.id, job_option_id: option.id)
      attach("JobOrderOption", old.id, "option_file", file)
      run(described_class)
      expect(attachments("JobTaskOption", task_option.id).pluck(:name, :blob_id)).to eq([["option_file", file.id]])
      expect(attachments("JobOrderOption", old.id).count).to eq(1)
    end

    it "does not guess when two task options match" do
      other = JobTask.create!(job_order: order, job_type: job_type, title: "Task #2")
      JobTaskOption.create!(job_task: other, job_option: option)
      old = insert("job_order_options", job_order_id: order.id, job_option_id: option.id)
      attach("JobOrderOption", old.id, "option_file", file)
      run(described_class)
      expect(ActiveStorage::Attachment.where(record_type: "JobTaskOption").count).to eq(0)
    end

    it "does not attach when two old files target the same task option" do
      old = insert("job_order_options", job_order_id: order.id, job_option_id: option.id)
      attach("JobOrderOption", old.id, "option_file", file)
      attach("JobOrderOption", old.id, "option_file", blob("second.pdf"))
      run(described_class)
      expect(ActiveStorage::Attachment.where(record_type: "JobTaskOption").count).to eq(0)
    end

    it "is idempotent, and down removes only what it attached" do
      old = insert("job_order_options", job_order_id: order.id, job_option_id: option.id)
      attach("JobOrderOption", old.id, "option_file", file)
      run(described_class)
      expect { run(described_class) }.not_to(change { ActiveStorage::Attachment.count })
      ActiveRecord::Migration.suppress_messages { described_class.new.down }
      expect(ActiveStorage::Attachment.where(record_type: "JobTaskOption").count).to eq(0)
      expect(attachments("JobOrderOption", old.id).count).to eq(1)
    end
  end

  describe ImportPrintOrdersAsJobOrders do
    let!(:three_d) { JobType.find_by(name: "3D Print") || create(:job_type, name: "3D Print") }
    let!(:laser) { JobType.find_by(name: "Laser Cut") || create(:job_type, name: "Laser Cut") }
    let!(:declined) { JobStatus.find_by(name: "Declined") || create(:job_status, name: "Declined") }
    let!(:picked_up) { JobStatus.find_by(name: "Picked-Up") || create(:job_status, name: "Picked-Up") }
    let(:created) { Time.utc(2020, 5, 4, 10, 0, 0) }

    def print_order(attrs = {})
      insert("print_orders", { user_id: user.id, order_type: 0, approved: true, quote: 12.345, comments: "High Quality",
                               comments_box: "box", staff_comments: "ok", comments_for_staff: "raise3d",
                               file_file_name: "part.stl", created_at: created, updated_at: created + 1.day }.merge(attrs))
    end

    let(:printed) { print_order(staff_id: staff.id, picked_up: true) }
    let(:file) { blob("part.stl") }
    let(:final) { blob("final.gcode") }
    let(:form) { blob("form.pdf") }

    before do
      attach("PrintOrder", printed.id, "file", file)
      attach("PrintOrder", printed.id, "final_file", final)
      attach("PrintOrder", printed.id, "pdf_form", form)
    end

    it "imports a print order as a closed job order with its task, quote, status and files" do
      run(described_class)
      order = JobOrder.find_by!(legacy_print_order_id: printed.id)
      expect(order).to have_attributes(user_id: user.id, assigned_staff_id: staff.id, job_type_id: three_d.id,
                                       user_comments: "High Quality\nbox", staff_comments: "ok\nraise3d",
                                       created_at: created, updated_at: created + 1.day)
      task = order.job_tasks.sole
      expect(task).to have_attributes(job_type_id: three_d.id, title: "part.stl")
      expect(task.job_task_quote.price).to eq(12.35)
      expect(order.total_price).to eq(12.35)
      expect(order.job_order_statuses.sole.job_status_id).to eq(picked_up.id)
      expect(task.user_files.map(&:blob_id)).to eq([file.id])
      expect(task.staff_files.map(&:blob_id)).to contain_exactly(final.id, form.id)
      expect(attachments("PrintOrder", printed.id).count).to eq(3)
      expect(ActiveStorage::Blob.count).to eq(3)
    end

    it "maps a declined laser-cut order, a missing quote, an unknown staff id and a missing file name" do
      declined_order = print_order(order_type: 1, approved: false, quote: nil, staff_id: 987_654, file_file_name: nil)
      attach("PrintOrder", declined_order.id, "file", blob("laser.svg"))
      run(described_class)
      order = JobOrder.find_by!(legacy_print_order_id: declined_order.id)
      expect(order).to have_attributes(job_type_id: laser.id, assigned_staff_id: nil)
      expect(order.job_order_statuses.sole.job_status_id).to eq(declined.id)
      expect(order.job_tasks.sole.title).to eq("laser.svg")
      expect(order.total_price).to eq(0)
    end

    it "is idempotent" do
      run(described_class)
      counts = -> { [JobOrder.count, JobTask.count, JobTaskQuote.count, JobOrderStatus.count, ActiveStorage::Attachment.count] }
      expect { run(described_class) }.not_to(change { counts.call })
    end

    it "down removes only the imported orders and leaves print orders and files" do
      native = JobOrder.create!(user: user, job_type: three_d)
      run(described_class)
      ActiveRecord::Migration.suppress_messages { described_class.new.down }
      expect(JobOrder.pluck(:id)).to eq([native.id])
      expect(JobTask.count).to eq(0)
      expect(attachments("PrintOrder", printed.id).count).to eq(3)
      expect(ActiveStorage::Attachment.where(record_type: "JobTask").count).to eq(0)
    end

    # One print order per flag combination class found in production.
    {
      "picked up and paid" => [{ approved: true, user_approval: true, printed: true, picked_up: true, payed: true }, :picked_up],
      "printed, not picked up" => [{ approved: true, user_approval: true, printed: true }, :declined],
      "printed and paid, not picked up" => [{ approved: true, user_approval: true, printed: true, payed: true }, :declined],
      "user declined" => [{ approved: true, user_approval: false }, :declined],
      "staff declined" => [{ approved: false }, :declined],
      "approved, never answered" => [{ approved: true }, :declined],
      "approved by both, not printed" => [{ approved: true, user_approval: true }, :declined],
      "no flags" => [{ approved: nil }, :declined]
    }.each do |label, (flags, expected)|
      it "closes a #{label} print order as #{expected == :picked_up ? 'Picked-Up' : 'Declined'}" do
        po = print_order({ approved: nil }.merge(flags))
        run(described_class)
        status = JobOrder.find_by!(legacy_print_order_id: po.id).job_order_statuses.sole
        expect(status.job_status_id).to eq(expected == :picked_up ? picked_up.id : declined.id)
      end
    end

    it "adds a blob that is both a final file and the PDF form once" do
      attach("PrintOrder", printed.id, "pdf_form", final)
      expect { run(described_class) }.not_to raise_error
      task = JobOrder.find_by!(legacy_print_order_id: printed.id).job_tasks.sole
      expect(attachments("JobTask", task.id).where(name: "staff_files", blob_id: final.id).count).to eq(1)
    end

    it "skips a print order whose user does not exist" do
      ghost = print_order(user_id: 987_654_321)
      run(described_class)
      expect(JobOrder.where(legacy_print_order_id: ghost.id)).to be_empty
      expect(JobOrder.where(legacy_print_order_id: printed.id)).to exist
    end

    it "stops on an unknown order_type and imports nothing" do
      print_order(order_type: 2)
      expect { ApplicationRecord.transaction(requires_new: true) { run(described_class) } }.to raise_error(ActiveRecord::StatementInvalid, /order_type/)
      expect(JobOrder.where.not(legacy_print_order_id: nil)).to be_empty
    end

    it "down refuses, leaving every row, when an imported order has other data" do
      run(described_class)
      order = JobOrder.find_by!(legacy_print_order_id: printed.id)
      order.job_quote_line_items.create!(description: "extra", price: 1)
      expect { ApplicationRecord.transaction(requires_new: true) { ActiveRecord::Migration.suppress_messages { described_class.new.down } } }
        .to raise_error(ActiveRecord::StatementInvalid, /changed after the import/)
      expect(JobOrder.where.not(legacy_print_order_id: nil).count).to eq(1)
      expect(order.job_tasks.count).to eq(1)
      expect(attachments("JobTask", order.job_tasks.first.id).count).to eq(3)
    end

    it "down refuses, leaving every row, when an imported quote price was edited" do
      run(described_class)
      quote = JobOrder.find_by!(legacy_print_order_id: printed.id).job_tasks.sole.job_task_quote
      quote.update!(price: 99)
      expect { ApplicationRecord.transaction(requires_new: true) { ActiveRecord::Migration.suppress_messages { described_class.new.down } } }
        .to raise_error(ActiveRecord::StatementInvalid, /changed after the import/)
      expect(quote.reload.price).to eq(99)
      expect(JobOrder.where.not(legacy_print_order_id: nil).count).to eq(1)
    end

    it "down refuses when an old quote was linked to an imported order" do
      run(described_class)
      order = JobOrder.find_by!(legacy_print_order_id: printed.id)
      order.update_columns(job_order_quote_id: insert("job_order_quotes", service_fee: 1).id)
      expect { ApplicationRecord.transaction(requires_new: true) { ActiveRecord::Migration.suppress_messages { described_class.new.down } } }
        .to raise_error(ActiveRecord::StatementInvalid, /changed after the import/)
      expect(JobOrder.where.not(legacy_print_order_id: nil).count).to eq(1)
    end

    it "down refuses a task file whose blob is on the print order under a name the import does not copy" do
      run(described_class)
      task = JobOrder.find_by!(legacy_print_order_id: printed.id).job_tasks.sole
      other = blob("other.pdf")
      attach("PrintOrder", printed.id, "extra", other)
      attach("JobTask", task.id, "staff_files", other)
      expect { ApplicationRecord.transaction(requires_new: true) { ActiveRecord::Migration.suppress_messages { described_class.new.down } } }
        .to raise_error(ActiveRecord::StatementInvalid, /changed after the import/)
      expect(attachments("JobTask", task.id).count).to eq(4)
    end

    it "down refuses when a file was added to an imported task" do
      run(described_class)
      task = JobOrder.find_by!(legacy_print_order_id: printed.id).job_tasks.sole
      attach("JobTask", task.id, "user_files", blob("later.stl"))
      expect { ApplicationRecord.transaction(requires_new: true) { ActiveRecord::Migration.suppress_messages { described_class.new.down } } }
        .to raise_error(ActiveRecord::StatementInvalid, /changed after the import/)
      expect(attachments("JobTask", task.id).count).to eq(4)
    end

    it "refuses to run when a required job type or status is missing" do
      declined.delete
      expect { run(described_class) }.to raise_error(ActiveRecord::StatementInvalid, /required/)
    end
  end
end
