#!/usr/bin/env bash

set -e;

if [[ -z "${ACTIONS_RUNTIME_URL}" ]]; then
	echo "::error::ACTIONS_RUNTIME_URL is missing. Uploading artifacts won't work without it. See https://github.com/KOLANICH-GHActions/passthrough-restricted-actions-vars and https://github.com/KOLANICH-GHActions/node_based_cmd_action_template";
	exit 1;
fi;

if [[ -z "${ACTIONS_RUNTIME_TOKEN}" ]]; then
	echo "::error::ACTIONS_RUNTIME_TOKEN is missing. Uploading artifacts won't work without it. See https://github.com/KOLANICH-GHActions/passthrough-restricted-actions-vars and https://github.com/KOLANICH-GHActions/node_based_cmd_action_template";
	exit 1;
fi;

NEED_PYTEST=$1;
SHOULD_ISOLATE_TESTING=$2;

THIS_SCRIPT_DIR=`dirname "${BASH_SOURCE[0]}"`; # /home/runner/work/_actions/KOLANICH-GHActions/typical-python-workflow/master
echo "This script is $THIS_SCRIPT_DIR";
THIS_SCRIPT_DIR=`realpath "${THIS_SCRIPT_DIR}"`;
echo "This script is $THIS_SCRIPT_DIR";
ACTIONS_DIR=`realpath "$THIS_SCRIPT_DIR/../../.."`;

ISOLATE="${THIS_SCRIPT_DIR}/isolate.sh";

AUTHOR_NAMESPACE=KOLANICH-GHActions;

SETUP_ACTION_REPO=$AUTHOR_NAMESPACE/setup-python;
GIT_PIP_ACTION_REPO=$AUTHOR_NAMESPACE/git-pip;
APT_ACTION_REPO=$AUTHOR_NAMESPACE/apt;
COVERAGEPY_ACTION_REPO=$AUTHOR_NAMESPACE/coveragepyReport;
CHECKOUT_ACTION_REPO=$AUTHOR_NAMESPACE/checkout;

SETUP_ACTION_DIR=$ACTIONS_DIR/$SETUP_ACTION_REPO/master;
GIT_PIP_ACTION_DIR=$ACTIONS_DIR/$GIT_PIP_ACTION_REPO/master;
APT_ACTION_DIR=$ACTIONS_DIR/$APT_ACTION_REPO/master;
COVERAGEPY_ACTION_DIR=$ACTIONS_DIR/$COVERAGEPY_ACTION_REPO/master;
CHECKOUT_ACTION_DIR=$ACTIONS_DIR/$CHECKOUT_ACTION_REPO/master;

if [ -d "$CHECKOUT_ACTION_DIR" ]; then
	:
else
	$ISOLATE git clone --depth=1 https://github.com/$CHECKOUT_ACTION_REPO $CHECKOUT_ACTION_DIR;
fi;

if [ -d "$SETUP_ACTION_DIR" ]; then
	:
else
	$ISOLATE bash "$CHECKOUT_ACTION_DIR/action.sh" "$SETUP_ACTION_REPO" "" "$SETUP_ACTION_DIR" 1 0;
fi;

if [ -d "$GIT_PIP_ACTION_DIR" ]; then
	:
else
	$ISOLATE bash "$CHECKOUT_ACTION_DIR/action.sh" "$GIT_PIP_ACTION_REPO" "" "$GIT_PIP_ACTION_DIR" 1 0;
fi;

if [ -d "$APT_ACTION_DIR" ]; then
	:
else
	$ISOLATE bash "$CHECKOUT_ACTION_DIR/action.sh" "$APT_ACTION_REPO" "" "$APT_ACTION_DIR" 1 0;
fi;

bash $SETUP_ACTION_DIR/action.sh $NEED_PYTEST;


$ISOLATE bash "$CHECKOUT_ACTION_DIR/action.sh" "$GITHUB_REPOSITORY" "$GITHUB_SHA" "$GITHUB_WORKSPACE" 1 1;

BEFORE_DEPS_COMMANDS_FILE="$GITHUB_WORKSPACE/.ci/beforeDeps.sh";
if [ -f "$BEFORE_DEPS_COMMANDS_FILE" ]; then
	echo "##[group] Running before deps commands";
	. $BEFORE_DEPS_COMMANDS_FILE ;
	echo "##[endgroup]";
fi;

echo "##[group] Installing dependencies";
bash $APT_ACTION_DIR/action.sh $GITHUB_WORKSPACE/.ci/aptPackagesToInstall.txt;
bash $GIT_PIP_ACTION_DIR/action.sh $GITHUB_WORKSPACE/.ci/pythonPackagesToInstallFromGit.txt;
echo "##[endgroup]";

echo "##[group] Getting package name";
PACKAGE_NAME=`$ISOLATE python3 $THIS_SCRIPT_DIR/getPackageName.py $GITHUB_WORKSPACE`;
echo "##[endgroup]";

cd "$GITHUB_WORKSPACE";

BEFORE_BUILD_COMMANDS_FILE="$GITHUB_WORKSPACE/.ci/beforeBuild.sh";
if [ -f "$BEFORE_BUILD_COMMANDS_FILE" ]; then
	echo "##[group] Running before build commands";
	. $BEFORE_BUILD_COMMANDS_FILE;
	echo "##[endgroup]";
fi;

echo "##[group] Building the main package";
$ISOLATE python3 -m build -xnw .;
PACKAGE_FILE_NAME=$PACKAGE_NAME-0.CI-py3-none-any.whl;
PACKAGE_FILE_PATH=./dist/$PACKAGE_FILE_NAME;
mv ./dist/*.whl $PACKAGE_FILE_PATH;
echo "##[endgroup]";

echo "##[group] Installing the main package";
$ISOLATE sudo pip3 install --upgrade $PACKAGE_FILE_PATH;
#$ISOLATE sudo pip3 install --upgrade -e $GITHUB_WORKSPACE;
echo "##[endgroup]";

#if [ "$GITHUB_REPOSITORY_OWNER" == "$GITHUB_ACTOR" ]; then
	if [ "$GITHUB_EVENT_NAME" == "push" ]; then
		echo "##[group] Uploading built wheels";
		python3 -m miniGHAPI artifact --name=$PACKAGE_FILE_NAME $PACKAGE_FILE_PATH;
		echo "##[endgroup]";
	else
		echo "Not uploading, event is $GITHUB_EVENT_NAME, not push";
	fi;
#else
#	echo "Not uploading, not owner, owner is $GITHUB_REPOSITORY_OWNER , you are $GITHUB_ACTOR";
#fi

TESTS_DIR=$GITHUB_WORKSPACE/tests;
if [[ -d "$TESTS_DIR/" ]]; then
	if [ $SHOULD_ISOLATE_TESTING ]; then
		ISOLATE_TESTING="";
	else
		ISOLATE_TESTING=$ISOLATE;
	fi
	if [ $NEED_PYTEST ]; then
		echo "##[group] testing with pytest and computing coverage";
		$ISOLATE_TESTING coverage run --branch --source=$PACKAGE_NAME -m pytest --junitxml=./rspec.xml $TESTS_DIR/*.py;
		python3 -m miniGHAPI artifact --name=rspec.xml rspec.xml;
	else
		echo "##[group] testing without pytest and computing coverage";
		$ISOLATE_TESTING coverage run --branch --source=$PACKAGE_NAME $TESTS_DIR/*.py;
		echo "for rspec.xml you would need pytest";
	fi;
	echo "##[endgroup]";

	if [[ -n "${INPUT_GITHUB_TOKEN}" ]]; then

		if [ -d "$COVERAGEPY_ACTION_DIR" ]; then
			:
		else
			$ISOLATE git clone --depth=1 https://github.com/$COVERAGEPY_ACTION_REPO $COVERAGEPY_ACTION_DIR;
		fi;

		INPUT_DATABASE_PATH=$GITHUB_WORKSPACE/.coverage INPUT_PACKAGE_NAME=$PACKAGE_NAME INPUT_PACKAGE_ROOT=$GITHUB_WORKSPACE bash $COVERAGEPY_ACTION_DIR/action.sh;
	else
		echo "No GitHub token is provided. If you want to annotate the code with coverage, set 'GITHUB_TOKEN' input variable";
	fi;

	if [[ -n "${CODECOV_TOKEN}" ]]; then
		echo "##[group] Uploading coverage to codecov";
		$ISOLATE codecov || true;
		echo "##[endgroup]";
	fi;
	if [[ -n "${COVERALLS_REPO_TOKEN}" ]]; then
		echo "##[group] Uploading coverage to coveralls";
		$ISOLATE coveralls || true;
		echo "##[endgroup]";
	fi;
fi;
