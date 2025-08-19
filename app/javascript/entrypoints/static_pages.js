import { driver } from "driver.js";
import "driver.js/dist/driver.css";
import {
  getCookie,
  setCookie,
  setCookieWithExp,
  translate,
  toggleLocale,
  removeURLParameter,
} from "./tour_utilities.js";

console.log(getCookie("tour_started"));

// Keeps track of the current step the tour is on incase a user switches the language mid-tour
let curStep = 0;

// Translations for each piece of text (will not be finalized until tour structure is decided upon)
const translations = {
  en: {
    "start-title": "Avant de commencer // Getting Started",
    "start-desc":
      "Veuillez sélectionner la langue de votre choix en utilisant le bouton le plus à droite. // Please select your language of choice using the rightmost button.",
    "step1-title": "Home Page",
    "step1-desc": "Welcome to MakerRepo. <Explain purpose of makerepo.com>.",
  },

  fr: {
    "start-title": "Avant de commencer // Getting Started",
    "start-desc":
      "Veuillez sélectionner la langue de votre choix en utilisant le bouton le plus à droite. // Please select your language of choice using the rightmost button.",
    "step1-title": "Home Page (French)",
    "step1-desc": "Bienvenue a MakerRepo. <Explain purpose of makerepo.com>.",
  },
};

// Tour translate button
const translateButton = document.createElement("button");
//Tour Steps
const driverObj = driver({
  popoverClass: "makerepo-theme",
  // Adding the Translate button
  onPopoverRender: (popover, { config, state }) => {
    if (window.location.search.includes("locale=en")) {
      translateButton.innerText = "FR";
    } else if (window.location.search.includes("locale=fr")) {
      translateButton.innerText = "EN";
    } else {
      translateButton.innerText = "FR";
    }

    popover.footerButtons.appendChild(translateButton);

    translateButton.addEventListener("click", () => {
      const urlParams = new URLSearchParams(window.location.search);
      toggleLocale(urlParams, curStep);
      window.location.search = urlParams;
    });
  },
  steps: [
    {
      popover: {
        title: translate("start-title", translations),
        description: translate("start-desc", translations),
        onNextClick: () => {
          curStep++;
          driverObj.moveNext();
          translateButton.hidden = true;
          console.log(curStep);
        },
      },
    },
    {
      // side: "top",
      // element: "#home",
      popover: {
        title: translate("step1-title", translations),
        description: translate("step1-desc", translations),
        onPrevClick: () => {
          curStep--;
          driverObj.movePrevious();
          translateButton.hidden = false;
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
          "Here on the home page, you can access plenty of essential information, such as when our spaces are open",
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
          "And what projects students have been working on recently.",
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
  console.log("hi");
  urlParams.set("tour", "0");

  window.location.search = urlParams;
});

if (getCookie("tour_started") === "") {
  setCookieWithExp("tour_started", "true", 1000);
  const urlParams = new URLSearchParams(window.location.search);
  curStep = Number(urlParams.get("tour"));
  driverObj.drive(Number(curStep));
} else if (window.location.search.includes("tour=0")) {
  const urlParams = new URLSearchParams(window.location.search);
  curStep = Number(urlParams.get("tour"));
  driverObj.drive(Number(curStep));
} else if (
  getCookie("tour_started") === "true" &&
  window.location.search.includes("tour")
) {
  console.log("made it");
  const urlParams = new URLSearchParams(window.location.search);
  curStep = Number(urlParams.get("tour"));
  driverObj.drive(Number(curStep));
}
