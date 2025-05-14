import { driver } from "driver.js";
import "driver.js/dist/driver.css";

const driverObj = driver({
  popoverClass: "makerepo-theme",
  steps: [
    {
      // side: "top",
      // element: "#home",
      popover: {
        title: "Home Page",
        description:
          "Welcome to MakerRepo. Please enjoy this tour of the website’s basic functionalities. ",
      },
    },
    {
      element: "#locale",
      popover: {
        title: "Translate Button",
        description:
          "First of all, select your preferred language using this button. // Tout d’abord, sélectionnez votre langue préférée à l’aide de ce bouton.",
      },
    },
    {
      element: "#home-hours",
      popover: {
        title: "Space Hours",
        description:
          "Here on the home page, you can access plenty of essential information, such as when our spaces are open. . .",
      },
    },
    {
      element: "#home-explore",
      popover: {
        title: "Explore Projects",
        description:
          "What projects students have been working on recently. . .",
      },
    },
    {
      element: "#home-makerstore",
      popover: {
        title: "Makerstore",
        description:
          "Or what materials are being sold at affordable prices in our Makerstore.",
        //onNextClick: () =>{

        // var x = document.querySelector("#projects-toggle");
        // if (x.style.display === "none") {
        //   console.log("about to display the dropdown")
        //   x.style.display = "block";
        // }
        // driverObj.moveNext();
        //}
      },
    },
    {
      element: "#home-workshops",
      popover: {
        title: "Workshops",
        description:
          "Be sure to check in here at the start of each week to find out what workshops will be happening.",
      },
    },
    {
      element: "#home-gen-res",
      popover: {
        title: "General Resources",
        description:
          "Request access to one of our spaces using the Makeroom page. Request us to build something using our tools and machinery using the Job Orders page.",
        onNextClick: () => {
          document.querySelector("#projects-toggle").click();
          driverObj.moveNext();
        },
      },
    },
    {
      element: "#projects-menu",
      popover: {
        title: "Projects",
        description:
          "CEED takes pride in providing students with the necessary tools to make their ideas come to life. Let’s take a look at what’s being made.",
        onNextClick: () => {
          Turbo.visit("/explore?tour=1");
          driverObj.moveNext();
        },
      },
    },
  ],
});

const btnTour = document.querySelector("#tour");

btnTour.addEventListener("click", () => {
  driverObj.drive();
});
