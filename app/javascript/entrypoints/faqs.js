import Sortable from "sortablejs";

document.addEventListener("turbo:load", () => {
  // On sort, POST to reorder
  function commitOrder(evt) {
    const reorderData = [...evt.to.children].map((i) => i.dataset.faqId);
    fetch("/faq/reorder", {
      method: "PUT",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        data: reorderData,
        format: "json",
      }),
    }).catch((error) => {
      console.log("Error reordering: " + error.message);
    });
  }

  const faqList = document.querySelector("#faqAccordion");
  let sortable = null;

  // Only enable with switch
  // Switch is shown only for admins
  // controller authenticates anyways
  const toggle = document.querySelector("#reorderSwitch");
  if (toggle) {
    toggle.addEventListener("change", (e) => {
      if (e.target.checked) {
        faqList.classList.add("sortEnable");
        sortable = new Sortable(faqList, {
          animation: 150,
          swapThreshold: 0.4,
          ghostClass: "bg-info-subtle",
          onSort: commitOrder,
        });
      } else {
        if (sortable) sortable.destroy();
        faqList.classList.remove("sortEnable");
      }
    });
  }
});
