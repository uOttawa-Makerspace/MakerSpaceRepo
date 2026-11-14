import TomSelect from "tom-select";
import { tomSelectOptions } from "../src/page_locale.js";
document.addEventListener("turbo:load", function () {
  if (document.getElementById("questions_trainings")) {
    if (!document.getElementById("questions_trainings").tomselect) {
      const trainings = /** @type {HTMLSelectElement} */ (
        document.getElementById("questions_trainings")
      );
      new TomSelect(
        trainings,
        tomSelectOptions(trainings, { plugins: ["clear_button"] }),
      );
    }
  }
  if (document.getElementById("pictureInput")) {
    document
      .getElementById("pictureInput")
      .addEventListener("change", function (event) {
        var files = event.target.files;
        var image = files;
        for (var i = 0; i < files.length; i++) {
          var reader = new FileReader();
          reader.onload = function (file) {
            var img = new Image();
            img.src = file.target.result;
            document.getElementById("image-target").insertBefore(img, null);
          };
          reader.readAsDataURL(image[i]);
        }
      });
  }
  if (document.getElementById("questions_trainings")) {
    if (!document.getElementById("questions_trainings").tomselect) {
      const trainings = /** @type {HTMLSelectElement} */ (
        document.getElementById("questions_trainings")
      );
      new TomSelect(
        trainings,
        tomSelectOptions(trainings, { plugins: ["clear_button"] }),
      );
    }
  }
});
