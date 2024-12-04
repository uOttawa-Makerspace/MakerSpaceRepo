import Sortable from "sortablejs";

document.addEventListener("turbo:load", function () {
  let linkList = document.querySelector("#linkList");
  new Sortable(linkList, {
    //handle: '.handle',
    animation: 150,
    onSort: function (evt) {
      const reorderData = [...evt.to.children].map(
        (el, order) => el.dataset.linkId
      );
      fetch("makerstore_links/reorder", {
        method: "PUT",
        headers: {
          Accept: "application/json",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          data: reorderData,
          format: "json",
        }),
      })
        .catch((error) => {
          console.log("Error reordering: " + error.message);
        })
        .then((response) => {
          Turbo.visit(window.location, { action: "replace" });
        });
    },
  });
});
