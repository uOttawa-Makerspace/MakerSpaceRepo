// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from "vitest";

const create = vi.fn();
vi.mock("../../app/javascript/channels/consumer", () => ({
  default: { subscriptions: { create: (...args) => create(...args) } },
}));

const { staffDashboardChannelConnection } =
  await import("../../app/javascript/channels/staff_dashboard_channel");

describe("staffDashboardChannelConnection", () => {
  beforeEach(() => {
    create.mockReset();
    document.body.innerHTML = "";
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
});
