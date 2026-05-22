import os
import subprocess
from pathlib import Path


PROJECT_ROOT = Path(os.getenv("PROJECT_ROOT", "/Users/mriduljoshi/Github/morocco-psp"))
PILOT_DATA_PATH = os.getenv(
    "PILOT_DATA_PATH",
    "/Users/mriduljoshi/Dropbox/DID - Morocco Pioneer Schools Year 3/4 - Data processing/03_Pilot/Clean/pilot_clean_20260518_mji.dta",
)


def run_step(cmd: list[str], step_name: str) -> None:
    env = os.environ.copy()
    env["PROJECT_ROOT"] = str(PROJECT_ROOT)
    env["PILOT_DATA_PATH"] = PILOT_DATA_PATH

    print(f"\n=== {step_name} ===")
    subprocess.run(cmd, cwd=PROJECT_ROOT, env=env, check=True)


def main() -> None:
    run_step(["Rscript", "analysis/pilot_psychometrics_review.R"], "Psychometrics review")
    run_step(["Rscript", "analysis/pilot_vertical_linking.R"], "Vertical linking")
    run_step(["python3", "analysis/pilot_item_action_sheet.py"], "Item action sheet")
    run_step(["python3", "analysis/pilot_reporting.py"], "Reporting")


if __name__ == "__main__":
    main()
