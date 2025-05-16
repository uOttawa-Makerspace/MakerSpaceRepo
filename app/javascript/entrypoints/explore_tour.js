import { driver } from "driver.js";
import "driver.js/dist/driver.css";
//import "./static_pages.js";

//console.log("Hello world!");

const driverObj = driver({
  popoverClass: "makerepo-theme",
  steps: [
    {
      popover: {
        title: "Explore Page",
        description:
          "This is where you can search for every student project ever posted to MakerRepo!",
      },
    },
    {
      element: "#explore-search",
      popover: {
        title: "Search",
        description:
          "You can search by the username of the creator or the name of the project.",
        onNextClick: () => {
          driverObj.moveNext();
          document.querySelector("#projects-toggle").click();
        },
      },
    },
    {
      element: "#become-a-client",
      popover: {
        title: "Project Proposals",
        description:
          "Want to make something of your own? You can submit a proposal right here.",
      },
    },
    {
      element: "#get-involved-menu",
      popover: {
        title: "Get Involved",
        description:
          "CEED offers a variety of opportunities for you to improve your skills such as workshops, volunteering, competitions, and much more.",
        onNextClick: () => {
          Turbo.visit("/get_involved?tour=1");
          driverObj.moveNext();
        },
      },
    },
  ],
});

driverObj.drive();
