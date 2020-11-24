#!/usr/bin/env python3
import typing
import sys
from pathlib import Path

import tomli

# pylint:disable=unused-argument,import-outside-toplevel

PyprojectTOML_T = typing.Dict[str, typing.Union[str, int, list]]


def extractFromPEP621(pyproject: PyprojectTOML_T) -> None:
	project = pyproject.get("project", None)
	if isinstance(project, dict):
		return project.get("name", None)

	return None


def getPackageName(rootDir: Path) -> str:
	tomlPath = Path(rootDir / "pyproject.toml")

	if tomlPath.is_file():
		with tomlPath.open("rb") as f:
			pyproject = tomli.load(f)

		fromPEP621 = extractFromPEP621(pyproject)
		if fromPEP621:
			return fromPEP621

		buildBackend = pyproject["build-system"].get("build-backend", "setuptools.build_meta").split(".")[0]
	else:
		buildBackend = "setuptools"
		pyproject = None
		print("pyproject.toml is not present, falling back to", buildBackend, file=sys.stderr)

	print("Build backend used: ", buildBackend, file=sys.stderr)

	return toolSpecificExtractors[buildBackend](pyproject, rootDir)


def extractFromFlit(pyproject: PyprojectTOML_T, rootDir: Path) -> str:
	tool = pyproject.get("tool", None)
	if isinstance(tool, dict):
		flit = tool.get("flit", None)
		if isinstance(flit, dict):
			metadata = flit.get("metadata", None)
			if isinstance(metadata, dict):
				name = metadata.get("dist-name", None)
				if name is None:
					name = metadata.get("module", None)
				if name:
					return name
	raise ValueError("Flit metadata is not present")


def extractFromPoetry(pyproject, rootDir):
	tool = pyproject.get("tool", None)
	if isinstance(tool, dict):
		poetry = tool.get("poetry", None)
		if isinstance(poetry, dict):
			name = poetry.get("name", None)
			if name:
				return name
	raise ValueError("Poetry metadata is not present")


def extractFromPDM(pyproject, rootDir):
	tool = pyproject.get("tool", None)
	if isinstance(tool, dict):
		pdm = tool.get("pdm", None)
		if isinstance(pdm, dict):
			name = pdm.get("name", None)
			if name:
				return name
	raise ValueError("PDM metadata is not present")


def extractFromSetuptools(pyproject: PyprojectTOML_T, rootDir: Path) -> str:
	setupCfgPath = Path(rootDir / "setup.cfg")
	setupPyPath = Path(rootDir / "setup.py")

	res = None

	if setupCfgPath.is_file():
		res = extractFromSetupCfg(setupCfgPath)

	if res:
		return res

	if setupPyPath.is_file():
		return extractFromSetupPy(setupPyPath)

	raise ValueError("setuptols metadata is not present")


def extractFromSetupCfg(setupCfgPath: Path) -> typing.Optional[str]:
	from setuptools.config import read_configuration

	setupCfg = read_configuration(setupCfgPath)
	try:
		return setupCfg["metadata"]["name"]
	except KeyError:
		return None


def extractFromSetupPy(setupPyPath: Path) -> str:
	import ast

	a = ast.parse(setupPyPath.read_text())

	def findSetupCall(a):
		for n in ast.walk(a):
			if isinstance(n, ast.Call):
				f = n.func
				if isinstance(f, ast.Name):
					if f.id == "setup":
						return n

		return None

	def findNameKeyword(setupCall):
		for kw in setupCall.keywords:
			if kw.arg == "name":
				return kw.value

		return None

	setupCall = findSetupCall(a)
	nameAst = findNameKeyword(setupCall)

	if isinstance(nameAst, ast.Name):
		raise ValueError("Not yet implemented")
	if isinstance(nameAst, ast.Str):
		return nameAst.value


toolSpecificExtractors = {
	"setuptools": extractFromSetuptools,
	"flit_core": extractFromFlit,
	"poetry": extractFromPoetry,
	"pdm": extractFromPDM,
}


def main():
	if len(sys.argv) > 1:
		p = sys.argv[1]
	else:
		p = "."
	print(getPackageName(Path(p)), file=sys.stdout)


if __name__ == "__main__":
	main()
