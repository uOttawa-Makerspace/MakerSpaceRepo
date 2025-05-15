import { driver } from "driver.js";
import "driver.js/dist/driver.css";

const locale = "en";

let curStep = 0;

// Translations for each piece of text (will not be finalized until tour structure is decided upon)
const translations = {
  en: {
    "start-title": "Getting Started // Avant de commencer",
    "start-desc":
      "Please select your language of choice using the rightmost button. // Veuillez sélectionner la langue de votre choix en utilisant le bouton le plus à droite.",
    "step1-title": "Home Page",
    "step1-desc":
      "Welcome to MakerRepo. Please enjoy this tour of the website's basic functionalities.",
  },

  fr: {
    "start-title": "Avant de commencer // Getting Started",
    "start-desc":
      "Veuillez sélectionner la langue de votre choix en utilisant le bouton le plus à droite. // Please select your language of choice using the rightmost button.",
    "step1-title": "Home Page (French)",
    "step1-desc": "Bienvenue a MakerRepo. . .",
  },
};

// Uses translations to find the according text given a key and a query parameter
function translate(text) {
  if (window.location.search.includes("locale=en")) {
    return translations.en[text];
  } else if (window.location.search.includes("locale=fr")) {
    return translations.fr[text];
  } else {
    return translations.en[text];
  }
}

// Toggles the locale of the entire site by changing the query parameter
function toggleLocale(urlParams) {
  console.log("0");
  if (window.location.search.includes("locale=en")) {
    console.log("1");
    urlParams.set("locale", "fr");
    urlParams.set("tour", curStep);
  } else if (window.location.search.includes("locale=fr")) {
    urlParams.set("locale", "en");
    console.log("2");
    urlParams.set("tour", curStep);
  } else {
    urlParams.set("locale", "fr");
    console.log("3");
    urlParams.set("tour", curStep);
  }
}

//Tour Steps
const driverObj = driver({
  popoverClass: "makerepo-theme",
  //Adding the Translate button
  onPopoverRender: (popover, { config, state }) => {
    const translateButton = document.createElement("button");
    if (window.location.search.includes("locale=en")) {
      translateButton.innerText = "FR";
    } else if (window.location.search.includes("locale=fr")) {
      translateButton.innerText = "EN";
    } else {
      translateButton.innerText = "FR";
    }

    popover.footerButtons.appendChild(translateButton);

    translateButton.addEventListener("click", () => {
      //toggleLocale(window.location.search.substr(1));
      const urlParams = new URLSearchParams(window.location.search);

      toggleLocale(urlParams);

      window.location.search = urlParams;
    });
  },
  steps: [
    {
      popover: {
        title: translate("start-title"),
        description: translate("start-desc"),
        onNextClick: () => {
          curStep++;
          driverObj.moveNext();
          console.log(curStep);
        },
      },
    },
    {
      // side: "top",
      // element: "#home",
      popover: {
        title: translate("step1-title"),
        description: translate("step1-desc"),
        onPrevClick: () => {
          curStep--;
          driverObj.movePrevious();
          console.log(curStep);
        },
        onNextClick: () => {
          curStep++;
          driverObj.moveNext();
          console.log(curStep);
        },
      },
    },
    {
      element: "#home-hours",
      popover: {
        title: "Space Hours",
        description:
          "Here on the home page, you can access plenty of essential information, such as when our spaces are open. . .",
        onPrevClick: () => {
          curStep--;
          driverObj.movePrevious();
          console.log(curStep);
        },
        onNextClick: () => {
          curStep++;
          driverObj.moveNext();
          console.log(curStep);
        },
      },
    },
    {
      element: "#home-explore",
      popover: {
        title: "Explore Projects",
        description:
          "What projects students have been working on recently. . .",
        onPrevClick: () => {
          curStep--;
          driverObj.movePrevious();
          console.log(curStep);
        },
        onNextClick: () => {
          curStep++;
          driverObj.moveNext();
          console.log(curStep);
        },
      },
    },
    // {
    //   element: "#home-makerstore",
    //   popover: {
    //     title: "Makerstore",
    //     description:
    //       "Or what materials are being sold at affordable prices in our Makerstore.",
    //   },
    // },
    // {
    //   element: "#home-workshops",
    //   popover: {
    //     title: "Workshops",
    //     description:
    //       "Be sure to check in here at the start of each week to find out what workshops will be happening.",
    //   },
    // },
    // {
    //   element: "#home-gen-res",
    //   popover: {
    //     title: "General Resources",
    //     description:
    //       "Request access to one of our spaces using the Makeroom page. Request us to build something using our tools and machinery using the Job Orders page.",

    //   },
    // },
    {
      element: "#projects",
      popover: {
        title: "Projects",
        description: "Let's take a look at what you can find under 'Projects'",
        onNextClick: () => {
          driverObj.moveNext();
          curStep++;
          // Opening a dropdown menu
          document.querySelector("#projects-toggle").click();
          console.log(curStep);
        },
        onPrevClick: () => {
          curStep--;
          driverObj.movePrevious();
          console.log(curStep);
        },
      },
    },
    {
      element: "#explore-projects",
      popover: {
        title: "Explore",
        description:
          "CEED takes pride in providing students with the necessary tools to make their ideas come to life. Let’s take a look at what’s being made.",
        onNextClick: () => {
          // Moving to another page and passing the query tour=1
          Turbo.visit("/explore?tour=1");
          driverObj.moveNext();
        },
        onPrevClick: () => {
          curStep--;
          console.log(curStep);
          driverObj.movePrevious();
        },
      },

      onPrevClick: () => {
        curStep--;
        // Closing a dropdown menu
        document.querySelector("#projects-toggle").click();
        console.log(curStep);
        driverObj.movePrevious();
      },
    },
  ],
});

const btnTour = document.querySelector("#tour");

//If the start tour button is clicked, set the query tour=1
btnTour.addEventListener("click", () => {
  //driverObj.drive();
  const urlParams = new URLSearchParams(window.location.search);

  urlParams.set("tour", "0");

  window.location.search = urlParams;
});

// If the query tour = 1 then start the tour. The locale parameter is always first, so we read from character 11
// to find the value of the tour param.
//console.log(window.location.search.substr(11));
if (
  window.location.search.substr(11, 4) === "tour" ||
  window.location.search.substr(1, 4) === "tour"
) {
  const urlParams = new URLSearchParams(window.location.search);
  curStep = Number(urlParams.get("tour"));
  console.log(curStep);
  driverObj.drive(Number(curStep));
}
