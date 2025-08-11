document.addEventListener("turbo:load", () => {
  [...document.getElementsByClassName("sk-delete-button")].forEach((btn) =>
    btn.addEventListener("click", (el) => {
      el.target.closest("button").parentNode.remove();
    }),
  );

  document.getElementById("new-sk").addEventListener("click", () => {
    const clone = document.getElementById("new-link-input").cloneNode(true);
    document.getElementById("link-container").append(clone);
    clone.removeAttribute("id");
    clone.querySelectorAll("input").forEach((input) => {
      input.value = "";
    });
    clone.querySelector("button").addEventListener("click", (el) => {
      el.target.closest("button").parentNode.remove();
    });
    clone.style.visibility = "visible";
  });
});

new TomSelect("#select-state", {
  valueField: "label",
  labelField: "label",
  searchField: ["label", "type"],
  // fetch remote data
  load: function (query, callback) {
    var self = this;
    if (self.loading > 1) {
      callback();
      return;
    }

    var url = "https://whatcms.org/API/List";
    fetch(url)
      .then((response) => response.json())
      .then((json) => {
        callback(json.result.list);
        self.settings.load = null;
      })
      .catch(() => {
        callback();
      });
  },
  // custom rendering function for options
  render: {
    option: function (item, escape) {
      return `<div class="py-2 d-flex">
							<div class="mb-1">
								<span class="h5">
									${escape(item.label)}
								</span>
							</div>
					 		<div class="ms-auto">${escape(item.type.join(", "))}</div>
						</div>`;
    },
  },
});

if (document.getElementById("search_bar")) {
  document
    .getElementById("search_bar")
    .addEventListener("keyup", function (event) {
      event.preventDefault();
      let query = document.getElementById("search_bar").value;
      if (query == "") {
        query = ".";
      }
      if (query.length > 2 || query == ".") {
        let url =
          "/admin/trainings/" +
          window.location.search("id") +
          "/edit?search=" +
          query;
        fetch(url, {
          method: "GET",
          headers: {
            Accept: "*/*",
          },
        })
          .then((response) => response.text())
          .then((data) => {
            document.getElementsByClassName("skills_list")[0].innerHTML = data;
          });
      }
    });
}
