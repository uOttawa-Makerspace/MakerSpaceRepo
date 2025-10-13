import consumer from "./consumer";

export function staffDashboardChannelConnection(modalCallback) {
  consumer.subscriptions.create(
    { channel: "StaffDashboardChannel" },
    {
      received(data) {
        modalCallback(data);
      },
    },
  );
}
