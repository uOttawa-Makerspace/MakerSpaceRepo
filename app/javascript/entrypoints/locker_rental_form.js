import TomSelect from "tom-select";

document.addEventListener("turbo:load", function () {
  // Search bar to pick an available locker
  document
    .querySelectorAll("#locker_rental_locker_id, #locker_id")
    .forEach((el) => {
      new TomSelect(el, {
        render: {
          option: function (data, escape) {
            let size = escape(data.size);
            let text = escape(data.text);
            return `<div>Locker ${text} - Size ${size}</div>`;
          },
          item: function (data, escape) {
            let size = escape(data.size);
            let text = escape(data.text);
            return `<div>Locker ${text} - Size ${size}</div>`;
          },
        },
      });
    });
});
