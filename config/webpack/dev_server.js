process.env.NODE_ENV = process.env.NODE_ENV || "dev_server";

const environment = require("./environment");

module.exports = environment.toWebpackConfig();
