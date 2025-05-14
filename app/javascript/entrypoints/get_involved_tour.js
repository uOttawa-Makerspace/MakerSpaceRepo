import { driver } from "driver.js";
import "driver.js/dist/driver.css";

console.log("Hello world!");

const driverObj = driver({
  popoverClass: "makerepo-theme",
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
      },
    },
    {
      element: "#profile-icon",
      popover: {
        title: "Your Profile",
        description: "Now let’s explore your profile page.",
      },
    },
  ],
});

driverObj.drive();
