"use strict";

const join = require("path").join;
const execSync = require("child_process").execSync;
const env = require("process").env;

const runCommand = "bash " + join(__dirname, "action.sh")

execSync(runCommand, {"stdio":"inherit"});
