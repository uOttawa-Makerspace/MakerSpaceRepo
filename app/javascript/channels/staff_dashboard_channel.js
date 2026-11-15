import consumer from "./consumer";

// The subscription of the page shown: each page load ends the previous page's
// one, so the dashboard follows its space once however often it is visited.
let subscription = null;

export function staffDashboardChannelConnection(modalCallback) {
  subscription?.unsubscribe();
  subscription = null;

  // The page that says the staff member has no space has no space field: nothing to follow.
  const spaceField = document.querySelector("#space_id");
  if (!spaceField) return;

  subscription = consumer.subscriptions.create(
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
