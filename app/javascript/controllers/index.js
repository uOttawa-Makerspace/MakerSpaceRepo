// Load all the controllers within this directory and all subdirectories.
// Controller files must be named *_controller.js.

// import { Application } from "@hotwired/stimulus";
// import { definitionsFromContext } from "@hotwired/stimulus-webpack-helpers";
//
// const application = Application.start();
// const context = require.context("controllers", true, /_controller\.js$/);
// application.load(definitionsFromContext(context));

import { Application } from "@hotwired/stimulus";
import { registerControllers } from "stimulus-vite-helpers";

const application = Application.start();
const controllers = import.meta.glob("./**/*.js", { eager: true });
registerControllers(application, controllers);
