import sys
import os
import subprocess
import json

BINARY_PATH="/home/user/fuzztruction/my-experiments/build/openvpn/consumer/openvpn"

covered = []

def main():
    if len(sys.argv) != 2:
        print("Usage: python compute_coverage.py <experiment_name>")
        sys.exit(1)

    experiment_name = sys.argv[1]
    profdata_dir = f"/home/user/fuzztruction/my-experiments/results/{experiment_name}/profdata"
    profdata_list = sorted(os.listdir(profdata_dir))
    
    # create the first merged profdata file
    merged_profdata = f"/home/user/fuzztruction/my-experiments/results/{experiment_name}/merged.profdata"
    os.system(f"llvm-profdata merge -o {merged_profdata} {profdata_dir}/{profdata_list[0]}")

    for profdata in profdata_list:
        timestamp = profdata.split(".")[0]
        os.system(f"llvm-profdata merge -o {merged_profdata} {merged_profdata} {profdata_dir}/{profdata}")
        # os.system(f"llvm-cov export -format=text -summary-only -instr-profile {merged_profdata} {BINARY_PATH} > coverage.json")
        result = subprocess.run(f"llvm-cov export -format=text -summary-only -instr-profile {merged_profdata} {BINARY_PATH}", shell=True, capture_output=True, text=True, check=True)
        data = json.loads(result.stdout)
        covered.append((timestamp,data["data"][0]["totals"]["branches"]["covered"]))
        print(f"Covered branches: {covered[-1]}")
    
    # save covered list to csv
    with open(f"/home/user/fuzztruction/my-experiments/results/{experiment_name}/covered.csv", "w") as f:
        f.write("timestamp,covered\n")
        for c in covered:
            f.write(f"{c[0]},{c[1]}\n")
        

if __name__ == "__main__":
    main()