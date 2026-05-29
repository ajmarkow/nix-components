# organize-tool - The file management automation tool
# https://github.com/tfeldmann/organize
# Not yet in nixpkgs, so we package it here.
{ lib
, python3
, fetchPypi
, ...
}:
let
  simplematch = python3.pkgs.buildPythonPackage rec {
    pname = "simplematch";
    version = "1.4";
    format = "pyproject";
    src = fetchPypi {
      inherit pname version;
      hash = "sha256-VadyeLPQaGyzjj/+WjJqX1nCmV8bofoaT2iHLBfK9Ms=";
    };
    nativeBuildInputs = [ python3.pkgs.poetry-core ];
    doCheck = false;
    meta = with lib; {
      description = "Minimal, super readable string pattern matching";
      license = licenses.mit;
    };
  };
in
python3.pkgs.buildPythonApplication rec {
  pname = "organize-tool";
  version = "3.3.0";
  src = fetchPypi {
    pname = "organize_tool";
    inherit version;
    hash = "sha256-A0/c+f/rI9IbSV4DhmUnjlifoE3HwMCgGko7MKBsU58=";
  };
  format = "pyproject";
  pythonRelaxDeps = true;
  nativeBuildInputs = [ python3.pkgs.poetry-core python3.pkgs.pythonRelaxDepsHook ];
  # Remove macos-tags dependency for build (not in nixpkgs; macOS tagging won't work)
  postPatch = ''
    sed -i '/macos-tags/d' pyproject.toml
  '';
  propagatedBuildInputs = with python3.pkgs; [
    arrow
    docopt-ng
    docx2txt
    exifread
    jinja2
    natsort
    pdfminer-six
    platformdirs
    pydantic
    pyyaml
    rich
    send2trash
    simplematch
  ];
  meta = with lib; {
    description = "The file management automation tool";
    homepage = "https://github.com/tfeldmann/organize";
    license = licenses.mit;
    mainProgram = "organize";
  };
}
