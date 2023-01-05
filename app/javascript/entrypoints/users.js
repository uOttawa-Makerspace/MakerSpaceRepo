document.addEventListener("turbo:load", function () {
  var elements = document.querySelectorAll("[data-show], [data-hide]");
  for (var i = 0; i < elements.length; i++) {
    elements[i].addEventListener("change", function () {
      var selector =
        this.getAttribute("data-show") || this.getAttribute("data-hide");
      var show = this.getAttribute("data-show") != null;
      var hide = this.getAttribute("data-hide") != null;
      var checked = this.checked;

      if ((show && checked) || (hide && !checked)) {
        document.querySelector(selector).style.display = show
          ? "block"
          : "none";
      }
    });

    if (elements[i].checked) {
      elements[i].dispatchEvent(new Event("change"));
    }
  }
});
