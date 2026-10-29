# Opens an ESP-IDF v5.0.1 environment in the current PowerShell session.
# Usage:  . .\tools\idf501.ps1        (note the leading dot)
#
# Kept separate from the ESP-IDF v5.4.2 install in C:\Espressif\esp-idf.
# v5.0.1 predates Python 3.12, so it runs on the Visual Studio Python 3.9.
# Its Python env needs these pins (already applied 2026-10-29):
#   setuptools<70  ruamel.yaml<0.18  ruamel.yaml.clib==0.2.8

$py39 = 'C:\Program Files (x86)\Microsoft Visual Studio\Shared\Python39_64'
$env:PATH = "$py39;$py39\Scripts;" + $env:PATH
$env:IDF_TOOLS_PATH = 'C:\Espressif\tools-v5.0.1'
$env:IDF_PATH = 'C:\Espressif\esp-idf-v5.0.1'
$env:IDF_PYTHON_ENV_PATH = 'C:\Espressif\tools-v5.0.1\python_env\idf5.0_py3.9_env'
. "$env:IDF_PATH\export.ps1"

# Windows' 260-character path limit breaks deep build trees, and this repo's
# path is long and contains a space. Build out of tree on a short path:
#   idf.py -B C:\Espressif\b\openmac set-target esp32c3
#   idf.py -B C:\Espressif\b\openmac build flash monitor
