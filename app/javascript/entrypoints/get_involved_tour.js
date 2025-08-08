import { driver } from "driver.js";
import "driver.js/dist/driver.css";
import { setURL } from "./tour_utilities";

console.log("Hello world!");

const tourEndButton = document.createElement("button");

const driverObj = driver({
  popoverClass: "makerepo-theme",
  onPopoverRender: (popover, { config, state }) => {
    tourEndButton.innerText = "End Tour";
    popover.footerButtons.appendChild(tourEndButton);

    tourEndButton.addEventListener("click", () => {
      removeURLParameter(window.location.href, "tour");
    });
    tourEndButton.hidden = true;
  },

  steps: [
    {
      popover: {
        title: "Get Involved",
        description: "Explore our many opportunities here!",
      },
    },
    {
      element: "#tour-signup",
      popover: {
        description:
          " If you are interested in signing up for a program, you are only one click away.",
        onNextClick: () => {
          driverObj.moveNext();
          tourEndButton.hidden = false;
        },
      },
    },
    {
      element: "#profile-icon",
      popover: {
        title: "Tour End",
        description: "That's all for this brief tour. Enjoy!",
        onNextClick: () => {
          driverObj.moveNext();
          setURL(window.location.href, "tour");
        },
      },
    },
  ],
});

driverObj.drive();
