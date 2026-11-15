import consumer from "./consumer";

// The live subscription of the page shown, the space it follows and the page's
// callback. A page load for the same space keeps the subscription; a load for
// another space, or for a page with no space field, ends it first.
let subscription = null;
let subscribedSpaceId = null;
let onMessage = null;

// The page that says the staff member has no space has no space field: nothing to follow.
function pageSpaceId() {
  return document.querySelector("#space_id")?.value ?? null;
}

export function staffDashboardChannelConnection(modalCallback) {
  onMessage = modalCallback;
  const spaceId = pageSpaceId();
  if (spaceId === subscribedSpaceId) return;

  subscription?.unsubscribe();
  subscription = null;
  subscribedSpaceId = spaceId;
  if (spaceId === null) return;

  subscription = consumer.subscriptions.create(
    {
      channel: "StaffDashboardChannel",
      space_id: spaceId,
    },
    {
      received(data) {
        onMessage(data);
      },
      // A refused subscription is forgotten, so the next load of the page subscribes again.
      rejected() {
        if (subscription !== this) return;
        subscription = null;
        subscribedSpaceId = null;
      },
    },
  );
}
