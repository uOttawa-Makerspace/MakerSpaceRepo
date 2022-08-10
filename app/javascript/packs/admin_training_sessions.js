document.getElementById("training_session_searchbar").addEventListener(
  "keyup",
  debounce(function (e) {
    let formData = document.getElementById("training_session_searchbar").value;
    let url = "/admin/training_sessions?search=" + formData;
    if (formData.length > 0 && formData != " ") {
      fetch(url).then((response) => {
        if (response.ok) {
          response.text().then((data) => {
            document.getElementsByClassName(
              "table-training-sessions"
            )[0].innerHTML = data;
          });
        }
      });
    }
  }, 100)
);
