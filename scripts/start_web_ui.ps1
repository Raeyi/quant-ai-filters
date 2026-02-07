param(
    [string]$Python = "python"
)

$ErrorActionPreference = "Stop"

& $Python .\\Python\\tools\\web_ui.py
