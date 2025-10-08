import consumer from "./consumer";

export function staffDashboardChannelConnection() {
  consumer.subscriptions.create(
    { channel: "StaffDashboardChannel" },
    {
      received(data) {
        console.log(data);
      },
    },
  );
}
