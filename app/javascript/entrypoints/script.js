import { driver } from "driver.js";
import "driver.js/dist/driver.css";
/*
const driverObj = driver();
driverObj.highlight({
  element: "#test",
  popover: {
    title: "This is a Test Button!",
    description: "Description"
  }
});

driverObj.drive();


const driverObj = driver.js.driver({
    showProgress: true,
    steps: [
        {
            element: "#test",
            popover: { title: "Test", description: "This is a test button!"}
        },
    ],
});

const btnTour = document.querySelector("#tour");

btnTour.addEventListener("click", () => {
    driverObj.drive();
})*/

document.addEventListener("DOMContentLoaded", function () {
  const testButton = document.getElementById("#tour");
  if (testButton) {
    testButton.addEventListener("click", () => {
      const driver = new Driver();
      driver.defineSteps([
        {
          element: "#test",
          popover: {
            title: "Test Button",
            description: "This starts the website tour.",
            position: "bottom",
          },
        },
      ]);
      driver.start();
    });
  } else {
    console.warn("Button with ID 'test' not found.");
  }
});
