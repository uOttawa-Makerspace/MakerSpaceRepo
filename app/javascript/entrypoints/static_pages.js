import { driver } from "driver.js";
import "driver.js/dist/driver.css";

const driverObj = driver({
  showProgress: true,
  steps: [
    {
      side: "top",
      element: "#home",
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
          "Purchase useful materials for your projects at our MakerStore!",
      },
    },
    {
      element: "#projects",
      popover: {
        title: "Projects",
        description:
          "CEED takes pride in providing students with the necessary tools to make their ideas come to life. Let’s take a look at what’s being made.",
        onNextClick: () => {
          //Turbo.visit('/explore')
          driverObj.moveNext();
        },
      },
    },
    {
      element: "#explore",
      popover: { title: "Explore Page", description: "test." },
    },
  ],
});

const btnTour = document.querySelector("#tour");

btnTour.addEventListener("click", () => {
  driverObj.drive();
});

/*
const driverObj1 = driver({
  showProgress: true,
  steps: [
        {
          element: "#explore",
          popover: { title: "Explore Page", description: "test."}
        },
  ],
});*/

/*
document.addEventListener("turbo:load", function () {
  const testButton = document.getElementById("tour");
  if (testButton) {
    testButton.addEventListener("click", () => {
      const driver = new Driver();
      driver.defineSteps([
        {
          element: "#test",
          popover: {
            title: "Test Button",
            description: "This starts the website tour.",
            position: "bottom"
          }
        }
      ]);
      driver.start();
    });
  } else {
    console.warn("Button with ID 'test' not found.");
  }
});*/
