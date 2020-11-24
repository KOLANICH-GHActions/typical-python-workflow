"use strict";

const join = require("path").join;
const execSync = require("child_process").execSync;
const env = require("process").env;

const runCommand = "bash " + join(__dirname, "action.sh") + " " + new Number(env["INPUT_USE_PYTEST"] == "true") + " " + new Number(env["INPUT_SHOULD_ISOLATE_TESTING"] == "true")

execSync(runCommand, {"stdio":"inherit"});
