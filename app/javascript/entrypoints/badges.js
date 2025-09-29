import TomSelect from "tom-select";
import DataTable from "datatables.net-bs5";
import "datatables.net-bs5/css/dataTables.bootstrap5.min.css";

let linkPP = document.querySelectorAll(".link-pp");
linkPP.forEach((link) => {
  if (!link.tomselect) {
    new TomSelect(link, {});
  }
});
if (document.getElementById("grant_user_select")) {
  if (!document.getElementById("grant_user_select").tomselect) {
    new TomSelect("#grant_user_select", {
      searchField: ["name"],
      valueField: "id",
      labelField: "name",
      options: [],
      maxOptions: 5,
      searchPlaceholder: "Choose User...",
      searchOnKeyUp: true,
      load: function (type, callback) {
        if (type.length < 2) {
          return;
        } else {
          let url = "/badges/populate_grant_users?search=" + type;
          fetch(url)
            .then((response) => response.json())
            .then((data) => {
              callback(
                data.users.map((user) => {
                  return { id: user.id, name: user.name };
                }),
              );
            });
        }
      },
      shouldLoad: function (type) {
        return type.length > 2;
      },
    });
  }
}
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
          headers: {
            Accept: "*/*",
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
          headers: {
            Accept: "*/*",
          },
        })
          .then((response) => response.text())
          .then((data) => {
            document.getElementsByClassName("badge_list")[0].innerHTML = data;
          });
      }
    });
}
if (document.getElementById("revoke_user_select")) {
  if (!document.getElementById("revoke_user_select").tomselect) {
    new TomSelect("#revoke_user_select", {
      searchField: ["name"],
      valueField: "id",
      labelField: "name",
      options: [],
      maxOptions: 5,
      searchPlaceholder: "Choose User...",
      searchOnKeyUp: true,
      load: function (type, callback) {
        if (type.length < 2) {
          return;
        } else {
          let url = "/badges/populate_revoke_users?search=" + type;
          fetch(url)
            .then((response) => response.json())
            .then((data) => {
              callback(
                data.users.map((user) => {
                  return { id: user.id, name: user.name };
                }),
              );
            });
        }
      },
      shouldLoad: function (type) {
        return type.length > 2;
      },
    });
  }
}

var download = document.querySelector("#add-to-linkedin");
download.addEventListener("click", downloadSVGAsPNG, false);

function downloadSVGAsText() {
  const svg = document.querySelector("svg");
  const base64doc = btoa(unescape(encodeURIComponent(svg.outerHTML)));
  const a = document.createElement("a");
  const e = new MouseEvent("click");
  a.download = "download.svg";
  a.href = "data:image/svg+xml;base64," + base64doc;
  a.dispatchEvent(e);
}

function downloadSVGAsPNG(e) {
  const canvas = document.createElement("canvas");
  const svg = document.querySelector("svg");
  const base64doc = btoa(unescape(encodeURIComponent(svg.outerHTML)));
  const w = 250;
  const h = 250;
  const img_to_download = document.createElement("img");
  img_to_download.src = "data:image/svg+xml;base64," + base64doc;
  console.log(w, h);
  img_to_download.onload = function () {
    console.log(base64doc);
    canvas.setAttribute("width", w);
    canvas.setAttribute("height", h);
    const context = canvas.getContext("2d");
    //context.clearRect(0, 0, w, h);
    context.drawImage(img_to_download, 0, 0, w, h);
    const dataURL = canvas.toDataURL("image/png");
    if (window.navigator.msSaveBlob) {
      console.log("save blob");
      window.navigator.msSaveBlob(canvas.msToBlob(), "download.png");
      e.preventDefault();
    } else {
      console.log("else");
      const a = document.createElement("a");
      const my_evt = new MouseEvent("click");
      a.download = "download.png";
      a.href = dataURL;
      a.dispatchEvent(my_evt);
    }
    //canvas.parentNode.removeChild(canvas);
  };
}

const downloadSVG = document.querySelector("#downloadSVG");
downloadSVG.addEventListener("click", downloadSVGAsText);
const downloadPNG = document.querySelector("#downloadPNG");
downloadPNG.addEventListener("click", downloadSVGAsPNG);

new DataTable("#badge-table");
new DataTable("#awarded-badge-table");
