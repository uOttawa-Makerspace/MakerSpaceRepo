function fadeOut(element, duration) {
  let periods = duration / 100;
  let opacity = 1;
  let interval = setInterval(() => {
    opacity -= 0.01;
    element.style.opacity = opacity;
    if (opacity <= 0) {
      clearInterval(interval);
    }
  }, periods);
}
function fadeIn(element, duration) {
  let periods = duration / 100;
  let opacity = 0;
  let interval = setInterval(() => {
    opacity += 0.01;
    element.style.opacity = opacity;
    if (opacity >= 1) {
      clearInterval(interval);
    }
  }, periods);
}
document.addEventListener("turbo:load", function (event) {
  // Can't find any references to this class other than this file and CSS. I can't tell where/if it gets assigned.
  // document.getElementsByClassName("select-styled").forEach(function(element){
  //   if (element.value == "Other"){
  //     fadeIn(element,1000);
  //   }else{
  //     fadeOut(element,1000);
  //   }
  // });

  [...document.getElementsByClassName("repository-container")].forEach(
    function (element) {
      element.addEventListener("mouseenter", function (event) {
        let wrapper = element.firstElementChild;
        if (wrapper.children.length >= 2) {
          fadeIn(wrapper.children[0], 100);
          fadeIn(wrapper.children[1], 100);
        }
      });
      element.addEventListener("mouseleave", function (event) {
        let wrapper = element.firstElementChild;
        if (wrapper.children.length >= 2) {
          fadeIn(wrapper.children[0], 100);
          fadeIn(wrapper.children[1], 100);
        }
      });
    }
  );

  [...document.getElementsByClassName("repository_report")].forEach(function (
    element
  ) {
    element.addEventListener("click", function (event) {
      [...document.getElementsByClassName("spinner")].forEach(function (
        element
      ) {
        element.style.display = "inline-block";
      });
    });
  });

  let filterHeader = document.getElementById("filter-header");
  if (filterHeader) {
    filterHeader.addEventListener("click", function (event) {
      let element = document.getElementById("sort-filter");
      if (element.style.display == "none" || element.style.display == "") {
        element.style.display = "block";
      } else {
        element.style.display = "none";
      }
    });
  }
  // Dropdown was fixed after commenting out this code -- keeping it here in case it's needed later
  // let categoryHeader = document.getElementById("category-header");
  // if (categoryHeader) {
  //   categoryHeader.addEventListener("click", function (event) {
  //     let element = document.getElementById("category-filter");
  //     if (element.style.display == "none" || element.style.display == "") {
  //       element.style.display = "block";
  //     } else {
  //       element.style.display = "none";
  //     }
  //   });
  // }
});
