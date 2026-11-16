if (document.getElementById("search_bar")) {
  document
    .getElementById("search_bar")
    .addEventListener("keyup", function (event) {
      event.preventDefault();
      let query = document.getElementById("search_bar").value;
      if (query == "") {
        let url = "/badges";
        fetch(url, {
          method: "GET",
          // the index.js.erb fragment is only served to same-origin XHR
          headers: {
            Accept: "*/*",
            "X-Requested-With": "XMLHttpRequest",
          },
        })
          .then((response) => response.text())
          .then((data) => {
            document.getElementsByClassName("badge_list")[0].innerHTML = data;
          });
      }
      if (query.length > 2 || query == ".") {
        let url = "/badges?search=" + query;
        fetch(url, {
          method: "GET",
          // the index.js.erb fragment is only served to same-origin XHR
          headers: {
            Accept: "*/*",
            "X-Requested-With": "XMLHttpRequest",
          },
        })
          .then((response) => response.text())
          .then((data) => {
            document.getElementsByClassName("badge_list")[0].innerHTML = data;
          });
      }
    });
}

document
  .querySelector("#add-to-linkedin")
  ?.addEventListener("click", downloadSVGAsPNG);

function downloadSVGAsPNG() {
  const canvas = document.createElement("canvas");
  const svg = document.querySelector("svg");
  const base64doc = btoa(unescape(encodeURIComponent(svg.outerHTML)));
  const w = 250;
  const h = 250;
  const img_to_download = document.createElement("img");
  img_to_download.src = "data:image/svg+xml;base64," + base64doc;
  img_to_download.onload = function () {
    canvas.setAttribute("width", w);
    canvas.setAttribute("height", h);
    canvas.getContext("2d").drawImage(img_to_download, 0, 0, w, h);
    const a = document.createElement("a");
    a.download = "download.png";
    a.href = canvas.toDataURL("image/png");
    a.dispatchEvent(new MouseEvent("click"));
  };
}
