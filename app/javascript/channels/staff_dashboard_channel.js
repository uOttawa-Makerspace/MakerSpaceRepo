import consumer from "./consumer";

export function staffDashboardChannelConnection(modalCallback) {
  // The page that says the staff member has no space has no space field: nothing to follow.
  const spaceField = document.querySelector("#space_id");
  if (!spaceField) return;

  consumer.subscriptions.create(
    {
      channel: "StaffDashboardChannel",
      space_id: spaceField.value,
    },
    {
      received(data) {
        modalCallback(data);
      },
    },
  );
}
