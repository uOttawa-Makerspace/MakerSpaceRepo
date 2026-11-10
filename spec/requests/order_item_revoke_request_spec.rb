# frozen_string_literal: true

require "rails_helper"

# Revoking an awarded project badge from the admin screen also deactivates the certification the
# approval granted (a soft demotion: the row stays), and approving the item again restores it.
RSpec.describe "Revoking a project badge", type: :request do
  include ContentSpecHelpers

  let(:training) { create(:training, skill: create(:skill, name: "Technical")) }
  let(:project) { create(:proficient_project, training: training) }
  let(:buyer) { create(:user, :volunteer_with_dev_program) }
  let(:item) do
    create(:order_item, order: create(:order, :completed, user_id: buyer.id), proficient_project: project,
                        status: "Waiting for approval")
  end
  let(:cert) { Certification.unscoped.find(ProficientProjectSession.find_by!(proficient_project: project).certification_id) }

  def approve(order_item)
    post approve_project_proficient_projects_path, params: { oi_id: order_item.id, order_item: { admin_comments: "ok" } }
  end

  def revoke(order_item)
    post order_item_revoke_path(order_item)
  end

  context "as an admin, after the item was approved" do
    let!(:admin) { content_sign_in_as(:admin) }

    before { approve(item) }

    it "marks the item revoked and deactivates its certification, keeping the row and the session" do
      expect(cert).to be_active
      expect { revoke(item) }.not_to change { [Certification.unscoped.count, ProficientProjectSession.count] }
      expect(response).to redirect_to(admin_index_path)
      expect(flash[:notice]).to eq("The badge has been revoked.")
      expect(item.reload.status).to eq("Revoked")
      cert.reload
      expect(cert.active).to be(false)
      expect(cert.demotion_reason).to eq(OrderItem::REVOKED_BADGE_REASON)
      expect(cert.demotion_staff).to eq(admin)
      expect(buyer.certifications).to be_empty
    end

    it "is safe to run twice" do
      revoke(item)
      expect { revoke(item) }.not_to change { cert.reload.attributes }
      expect(item.reload.status).to eq("Revoked")
      expect(Certification.unscoped.where(user_id: buyer.id).count).to eq(1)
    end

    it "restores the certification when the item is approved again, and a second approval changes nothing" do
      revoke(item)
      approve(item)
      expect(item.reload.status).to eq("Awarded")
      expect(cert.reload).to be_active
      expect(cert.demotion_reason).to be_nil
      expect(cert.demotion_staff).to be_nil
      expect { approve(item) }.not_to change { [Certification.unscoped.count, ProficientProjectSession.count] }
      expect(flash[:error]).to include("no longer waiting")
    end

    it "leaves a certification an admin demoted by hand alone when the item is approved again" do
      revoke(item)
      cert.update!(demotion_reason: "manual")
      approve(item)
      expect(item.reload.status).to eq("Revoked")
      expect(cert.reload).not_to be_active
    end
  end

  it "keeps the certification while another awarded item of the same user and project backs it" do
    content_sign_in_as(:admin)
    approve(item)
    other = create(:order_item, order: create(:order, :completed, user_id: buyer.id), proficient_project: project,
                                status: "Awarded")
    revoke(item)
    expect(item.reload.status).to eq("Revoked")
    expect(other.reload.status).to eq("Awarded")
    expect(cert.reload).to be_active
  end

  it "refuses a staff member who is not an admin and changes nothing" do
    content_sign_in_as(:admin)
    approve(item)
    delete logout_path rescue nil
    content_sign_in_as(:staff)
    revoke(item)
    expect(response).to have_http_status(:forbidden)
    expect(item.reload.status).to eq("Awarded")
    expect(cert.reload).to be_active
  end

  it "does not touch a certification when a submission that was never approved is revoked" do
    content_sign_in_as(:admin)
    other_cert = create(:certification, user: buyer)
    expect { revoke(item) }.not_to change { Certification.unscoped.count }
    expect(item.reload.status).to eq("Revoked")
    expect(other_cert.reload).to be_active
  end
end
