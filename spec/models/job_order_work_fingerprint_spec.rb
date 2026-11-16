# frozen_string_literal: true

require "rails_helper"

# The work fingerprint decides whether a paid or quoted order still asks for the same work. Its exact value is
# pinned here for every input shape: the rows are written out in full and digested the same way, so any change to
# what goes in, its order or its serialization changes the expected digest.
RSpec.describe JobOrder, "#work_fingerprint", type: :model do
  let(:owner) { create(:user, :regular_user) }
  let(:order) { create(:job_order, user: owner) }
  let(:job_type) { create(:job_type) }
  let(:group) { create(:job_service_group, job_type: job_type) }
  let(:service) { create(:job_service, job_service_group: group, name: "Nylon") }

  def blob!(name)
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new(name), filename: name, content_type: "model/x.stl-binary")
  end

  def digest(rows)
    Digest::SHA256.hexdigest(rows.to_json)
  end

  def fingerprint
    described_class.find(order.id).work_fingerprint
  end

  it "is the digest of an empty list for an order without tasks" do
    expect(fingerprint).to eq(digest([]))
    expect(fingerprint).to eq("4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945")
  end

  it "leaves out a blank task (no type, service, options or files)" do
    order.job_tasks.create!(title: "Blank")
    expect(fingerprint).to eq(digest([]))
  end

  it "lists a task with only a job type, with a nil service and service name" do
    task = order.job_tasks.create!(title: "Typed", job_type: job_type)
    expect(fingerprint).to eq(digest([[task.id, job_type.id, nil, nil, [], [], []]]))
  end

  it "lists a task with a service and the service's current name" do
    task = order.job_tasks.create!(title: "Serviced", job_type: job_type, job_service: service)
    expect(fingerprint).to eq(digest([[task.id, job_type.id, service.id, "Nylon", [], [], []]]))

    JobService.where(id: service.id).update_all(name: "Nylon 12") # rubocop:disable Rails/SkipsModelValidations
    expect(fingerprint).to eq(digest([[task.id, job_type.id, service.id, "Nylon 12", [], [], []]]))
  end

  it "lists a task with only options, sorted by option id then file blob id, a missing file as nil" do
    task = order.job_tasks.create!(title: "Options")
    first, second = create_list(:job_option, 2).sort_by(&:id)
    with_file = task.job_task_options.create!(job_option: second)
    with_file.option_file.attach(blob!("opt.stl"))
    task.job_task_options.create!(job_option: first)
    blob_id = with_file.reload.option_file.blob.id

    expect(fingerprint).to eq(digest([[task.id, nil, nil, nil, [[first.id, nil], [second.id, blob_id]], [], []]]))
  end

  it "sorts two rows of the same option by file blob id, a missing file first" do
    task = order.job_tasks.create!(title: "Same option")
    option = create(:job_option)
    with_file = task.job_task_options.create!(job_option: option)
    with_file.option_file.attach(blob!("same.stl"))
    task.job_task_options.create!(job_option: option)
    blob_id = with_file.reload.option_file.blob.id

    expect(fingerprint).to eq(digest([[task.id, nil, nil, nil, [[option.id, nil], [option.id, blob_id]], [], []]]))
  end

  it "lists a task with only user files, sorted by blob id" do
    task = order.job_tasks.create!(title: "User files")
    blobs = [blob!("b.stl"), blob!("a.stl")]
    blobs.each { |b| task.user_files.attach(b) }

    expect(fingerprint).to eq(digest([[task.id, nil, nil, nil, [], blobs.map(&:id).sort, []]]))
  end

  it "lists a task with only staff files, sorted by blob id" do
    task = order.job_tasks.create!(title: "Staff files")
    blobs = [blob!("d.stl"), blob!("c.stl")]
    blobs.each { |b| task.staff_files.attach(b) }

    expect(fingerprint).to eq(digest([[task.id, nil, nil, nil, [], [], blobs.map(&:id).sort]]))
  end

  it "lists every part of a full task and orders tasks by id, skipping blank ones between them" do
    option = create(:job_option)
    full = order.job_tasks.create!(title: "Full", job_type: job_type, job_service: service)
    full.job_task_options.create!(job_option: option)
    user_blob = blob!("u.stl")
    staff_blob = blob!("s.stl")
    full.user_files.attach(user_blob)
    full.staff_files.attach(staff_blob)
    order.job_tasks.create!(title: "Blank")
    typed = order.job_tasks.create!(title: "Typed", job_type: job_type)

    expect(fingerprint).to eq(
      digest([
               [full.id, job_type.id, service.id, "Nylon", [[option.id, nil]], [user_blob.id], [staff_blob.id]],
               [typed.id, job_type.id, nil, nil, [], [], []]
             ])
    )
  end

  it "does not depend on task titles, quotes or the order's own columns" do
    task = order.job_tasks.create!(title: "Typed", job_type: job_type)
    before = fingerprint
    task.update!(title: "Renamed")
    task.create_job_task_quote!(price: 12)
    order.update!(staff_comments: "changed")

    expect(fingerprint).to eq(before)
  end
end
