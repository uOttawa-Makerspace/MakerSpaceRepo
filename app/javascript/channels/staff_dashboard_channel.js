import consumer from "./consumer";

export function staffDashboardChannelConnection(modalCallback) {
  consumer.subscriptions.create(
    {
      channel: "StaffDashboardChannel",
      space_id: document.querySelector("#space_id").value,
    },
    {
      received(data) {
        modalCallback(data);
      },
    },
  );
}
