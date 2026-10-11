#!/usr/bin/env python3
"""Merge parameters.json with env overrides for CloudFormation deploy."""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path


def main() -> None:
    base_path = Path(os.environ.get("CFN_PARAMETERS_BASE", "parameters.json"))
    out_path = Path(os.environ.get("CFN_PARAMETERS_OUT", "jenkins-parameters.json"))
    base = json.loads(base_path.read_text(encoding="utf-8"))
    by_key = {p["ParameterKey"]: p for p in base}

    env_map = {
        "ExistingEc2KeyName": "EXISTING_EC2_KEY_NAME",
        "BastionSshCidrs": "BASTION_SSH_CIDRS",
        "S3BucketName": "S3_BUCKET_NAME",
        "CfnTemplateBucket": "CFN_TEMPLATE_BUCKET",
        "HarborUsername": "HARBOR_USERNAME",
        "HarborPassword": "HARBOR_PASSWORD",
        "DeploySpendSmart": "DEPLOY_SPENDSMART",
    }
    for param_key, env_key in env_map.items():
        val = os.environ.get(env_key)
        if val is not None and str(val).strip() != "":
            by_key[param_key] = {"ParameterKey": param_key, "ParameterValue": str(val)}

    if os.environ.get("HARBOR_USERNAME") and os.environ.get("HARBOR_PASSWORD"):
        by_key["DeploySpendSmart"] = {
            "ParameterKey": "DeploySpendSmart",
            "ParameterValue": os.environ.get("DEPLOY_SPENDSMART", "true"),
        }

    out_path.write_text(json.dumps(list(by_key.values()), indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {out_path} ({len(by_key)} parameters)")


if __name__ == "__main__":
    main()
