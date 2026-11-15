// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from "vitest";

const create = vi.fn();
vi.mock("../../app/javascript/channels/consumer", () => ({
  default: { subscriptions: { create: (...args) => create(...args) } },
}));

const { staffDashboardChannelConnection } =
  await import("../../app/javascript/channels/staff_dashboard_channel");

const subscribeOnDashboard = (spaceId = "7") => {
  document.body.innerHTML = `<input id="space_id" value="${spaceId}">`;
  staffDashboardChannelConnection(vi.fn());
};

describe("staffDashboardChannelConnection", () => {
  beforeEach(() => {
    // A load of a page with no space field ends any subscription left by an earlier example.
    document.body.innerHTML = "";
    staffDashboardChannelConnection(vi.fn());
    create.mockReset();
    create.mockImplementation(() => ({ unsubscribe: vi.fn() }));
  });

  it("subscribes to the space named by the page's space field", () => {
    document.body.innerHTML = '<input id="space_id" value="7">';
    const callback = vi.fn();
    staffDashboardChannelConnection(callback);
    expect(create).toHaveBeenCalledTimes(1);
    const [params, handlers] = create.mock.calls[0];
    expect(params).toEqual({ channel: "StaffDashboardChannel", space_id: "7" });
    handlers.received({ add_user: 1 });
    expect(callback).toHaveBeenCalledWith({ add_user: 1 });
  });

  it("does not subscribe on a page with no space field", () => {
    staffDashboardChannelConnection(vi.fn());
    expect(create).not.toHaveBeenCalled();
  });

  it("keeps the subscription when the page loads again for the same space", () => {
    subscribeOnDashboard("7");
    const subscription = create.mock.results[0].value;
    const handlers = create.mock.calls[0][1];
    const latest = vi.fn();
    document.body.innerHTML = '<input id="space_id" value="7">';
    staffDashboardChannelConnection(latest);
    expect(subscription.unsubscribe).not.toHaveBeenCalled();
    expect(create).toHaveBeenCalledTimes(1);
    handlers.received({ add_user: 2 });
    expect(latest).toHaveBeenCalledWith({ add_user: 2 });
  });

  it("ends the previous space's subscription before following another space", () => {
    subscribeOnDashboard("7");
    const first = create.mock.results[0].value;
    subscribeOnDashboard("8");
    expect(first.unsubscribe).toHaveBeenCalledTimes(1);
    expect(create).toHaveBeenCalledTimes(2);
    expect(create.mock.results[1].value.unsubscribe).not.toHaveBeenCalled();
  });

  it("ends the dashboard's subscription when a page with no space field loads", () => {
    subscribeOnDashboard();
    const subscription = create.mock.results[0].value;
    document.body.innerHTML = "";
    staffDashboardChannelConnection(vi.fn());
    expect(subscription.unsubscribe).toHaveBeenCalledTimes(1);
    staffDashboardChannelConnection(vi.fn());
    expect(subscription.unsubscribe).toHaveBeenCalledTimes(1);
  });
});
