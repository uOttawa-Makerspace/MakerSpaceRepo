import TomSelect from "tom-select";

document.addEventListener("turbo:load", function () {
  // Search bar to pick an available locker
  new TomSelect("#locker_rental_locker_id", {
    searchPlaceholder: "Select a locker...",
    render: {
      option: (data, escape) => {
        console.log(data);
        return `<div>${escape(data.text)}</div>`;
      },
    },
  });

  if (document.querySelector("#locker_id")) {
    new TomSelect("#locker_id");
  }
});
