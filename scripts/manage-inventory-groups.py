#!/usr/bin/env python3

import argparse
import json
import logging
import subprocess as s
import sys
from enum import Enum
from pathlib import Path

__LogLevel = logging.INFO

if __LogLevel == logging.DEBUG:
    logging.basicConfig(
        format="[%(levelname)s][%(asctime)s][%(funcName)s][%(lineno)d] - %(message)s",
        level=logging.DEBUG,
    )
else:
    logging.basicConfig(
        format="--> %(levelname)-.4s: %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
        level=logging.INFO,
    )

logger = logging.getLogger("TRON")


class Operation(Enum):
    audit = "audit"
    restore = "restore"

    def __str__(self) -> str:
        return self.value


## key is group/kind/name
__lookups = {
    "apps/Deployment/cert-manager": "eda-external-packages/cert-manager",
    # namespace group=""
    "/Namespace/eda-system": "eda-external-packages/eda-core-ns",
    "apps/Deployment/eda-git": "eda-external-packages/git",
    "apps/DaemonSet/cert-manager-csi-driver": "eda-external-packages/csi-driver",
    "apps/Deployment/trust-manager": "eda-external-packages/trust-manager",
    "cert-manager.io/Certificate/eda-api-ca": "eda-external-packages/eda-issuer-api",
    "cert-manager.io/Certificate/eda-node-ca": "eda-external-packages/eda-issuer-node",
    "cert-manager.io/Issuer/eda-root-ca-issuer": "eda-external-packages/eda-issuer-root",
    "apps/Deployment/eda-fluentd": "eda-external-packages/fluentd",
    "apps/Deployment/eda-ce": "eda-kpt-base",
    "core.eda.nokia.com/IndexAllocationPool/asn-pool": "eda-kpt-playground",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--eda-kpt-location",
        type=Path,
        required=True,
        help="Location of the kpt repo",
    )

    parser.add_argument(
        "--kubectl", required=True, type=Path, help="path of the kubectl binary"
    )

    parser.add_argument("--yq", required=True, type=Path, help="path of the yq binary")

    parser.add_argument(
        "--operation",
        required=False,
        type=Operation,
        default=Operation.audit,
        choices=list(Operation),
        help="What action to take for inventories in a cluster ?",
    )

    return parser.parse_args()


def die(msg: any, exit_code: int = 127) -> None:
    logger.critical(msg)
    sys.exit(exit_code)


def kubectl(kubectl_bin: Path, kcmd: str, outputJson: bool = True):
    _cmd = f"{kubectl_bin} {kcmd}"

    if outputJson:
        _cmd = f"{_cmd} -o json"

    logger.debug(f"Running {_cmd}")

    ret = s.run(_cmd, shell=True, executable="/bin/bash", stdout=s.PIPE, stderr=s.PIPE)

    if ret.returncode != 0:
        die(
            f"Could not execute {_cmd} got: "
            f"- exit code {ret.returncode} "
            f"- stderr: {ret.stderr.decode('utf-8')} "
            f"- stdout: {ret.stdout.decode('utf-8')}",
            ret.returncode,
        )

    output = ret.stdout.decode("utf-8")
    logger.debug(f"Ran {_cmd} got {output}")

    if outputJson:
        return json.loads(output)

    return output


def yq_load(yq_bin: Path, input: Path):
    _cmd = f"{yq_bin} -o json --no-colors {input}"

    logger.debug(f"Running {_cmd}")

    ret = s.run(_cmd, shell=True, executable="/bin/bash", stdout=s.PIPE, stderr=s.PIPE)

    if ret.returncode != 0:
        die(
            f"Could not execute {_cmd} got: "
            f"- exit code {ret.returncode} "
            f"- stderr: {ret.stderr.decode('utf-8')} "
            f"- stdout: {ret.stdout.decode('utf-8')}",
            ret.returncode,
        )

    output = ret.stdout.decode("utf-8")
    logger.debug(f"Ran {_cmd} got {output}")

    return json.loads(output)


def yq_dump(yq_bin: Path, contents: dict, output: Path) -> None:
    _cmd = f"{yq_bin} --input-format=json --no-colors > {output}"

    data = json.dumps(contents)  # Convert it to a string

    ret = s.run(
        _cmd,
        shell=True,
        executable="/bin/bash",
        input=data,
        text=True,
        stdout=s.PIPE,
        stderr=s.PIPE,
    )

    if ret.returncode != 0:
        die(
            f"Could not execute {_cmd} got: "
            f"- exit code {ret.returncode} "
            f"- stderr: {ret.stderr} "
            f"- stdout: {ret.stdout}",
            ret.returncode,
        )

    return


def process_resourcegroups(data: dict, markers: dict[str, str]):
    # Keys for things in dicts
    key_items = "items"
    key_kind = "kind"
    val_kind = "ResourceGroup"

    if key_items not in data:
        die(
            f"Did not find any {key_items} in {data}, did it run against the right cluster ?",
            127,
        )

    rgs = data[key_items]

    logger.info(f"Processing {len(rgs)} resource groups")

    if len(rgs) == 0:
        logger.warning("No resource groups found, is this cluster initialized ?")
        return {}

    inventories = {}  # Key is path where to write and val is content from the cluster

    for rg in rgs:
        if rg[key_kind] != "ResourceGroup":
            logger.warning(f"Resource type {rg[key_kind]} != {val_kind} skipping")
            continue

        inventory_metadata = rg["metadata"]
        inventory_name = inventory_metadata["name"]
        inventory_resources = rg["spec"]["resources"]

        logger.debug(f"Processing {inventory_name}")
        found = False
        for r in inventory_resources:
            beacon = f"{r['group']}/{r['kind']}/{r['name']}"
            if beacon in markers:
                inventory_path = markers[beacon]
                if inventory_path in inventories:
                    die(
                        f"Found duplicated marker resources in searching for kpt packages {beacon} - {inventories}"
                    )
                else:
                    found = True
                    inventories[inventory_path] = {
                        "inventoryName": inventory_name,
                        "fromCluster": rg,
                        "toPkg": {
                            "apiVersion": "kpt.dev/v1alpha1",
                            "kind": "ResourceGroup",
                            "metadata": {
                                "name": inventory_name,
                                "namespace": inventory_metadata["namespace"],
                                "labels": inventory_metadata["labels"],
                            },
                        },
                    }
                    logger.info(f"Matched {inventory_name} to package {inventory_path}")

        if not found:
            logger.warning(f"Could not match {inventory_name} to known resources")

    logger.info(f"Matched {len(inventories)}/{len(rgs)} inventory resource groups")
    logger.debug("Correlated the below inventories")
    logger.debug(inventories)

    return inventories


def write_inventories(inventories: dict, kpt_root: Path, yq_bin: Path):
    logger.info(f"Updating package inventories in: {kpt_root}")
    for inventory_path, inventory_data in sorted(inventories.items()):
        resourcegroup_file: Path = kpt_root / inventory_path / "resourcegroup.yaml"
        resource_group = inventory_data["toPkg"]
        inventory_name = inventory_data["inventoryName"]
        logger.debug(f"Processing {resourcegroup_file}")

        write_to_pkg = True

        if resourcegroup_file.is_file():
            logger.debug(f"{resourcegroup_file} exists - loading it")
            resource_on_disk = yq_load(yq_bin, resourcegroup_file)

            if resource_on_disk == resource_group:
                write_to_pkg = False
                logger.info(f"Already up to date {inventory_name}: {inventory_path}")

        if write_to_pkg:
            yq_dump(yq_bin, inventory_data["toPkg"], resourcegroup_file)
            logger.info(
                f"Wrote {inventory_data['inventoryName']}: {resourcegroup_file}"
            )


def audit_inventories(inventories: dict, kpt_root: Path, yq_bin: Path):
    logger.info(f"Auditing package inventories in: {kpt_root}")
    for inventory_path, inventory_data in sorted(inventories.items()):
        resourcegroup_file: Path = kpt_root / inventory_path / "resourcegroup.yaml"
        resource_group = inventory_data["toPkg"]
        inventory_name = inventory_data["inventoryName"]

        if resourcegroup_file.is_file():
            logger.debug(f"{resourcegroup_file} exists - loading it")
            resource_on_disk = yq_load(yq_bin, resourcegroup_file)

            if resource_on_disk != resource_group:
                logger.warning(
                    f"{inventory_path} differs from cluster inventory - updated needed"
                )
                logger.debug(f"KPT Cluster: {resource_group}")
                logger.debug(f"KPT Disk: {resource_on_disk}")
            else:
                logger.info(f"Already up to date {inventory_name}: {inventory_path}")
        else:
            logger.warning(
                f"{inventory_path} package is not initialized - can be recovered from cluster"
            )


def is_crd_installed(kubectl_bin: Path, crdName: str) -> bool:
    logger.debug(f"Searching for {crdName}")

    _cmd = "get customresourcedefinitions.apiextensions.k8s.io -o=jsonpath=\"{.items[*]['metadata.name']}\""
    getcrds = kubectl(kubectl_bin, _cmd, False)
    logger.debug(f"Found installed crds {getcrds}")

    crds = getcrds.split(sep=" ")
    if crdName in crds:
        logger.info(f"Found {crdName} installed in cluster")
        return True

    return False


def main() -> int:
    args = parse_args()
    kpt = args.eda_kpt_location.absolute()
    kubectl_bin = args.kubectl.absolute()
    yq_bin = args.yq.absolute()
    op = args.operation

    rgCRDName = "resourcegroups.kpt.dev"

    logger.info(f"Args - kpt: {kpt}, kubectl: {kubectl_bin}, yq: {yq_bin}")

    if is_crd_installed(kubectl_bin, rgCRDName) is False:
        logger.info(
            f"{rgCRDName} crd is not installed in cluster - no inventories to recover"
        )
        return 0

    logger.info("Retrieving resource groups")

    resourcegroups = kubectl(kubectl_bin, "get resourcegroups.kpt.dev -A")

    inventories = process_resourcegroups(resourcegroups, __lookups)

    if op == Operation.audit:
        audit_inventories(inventories, kpt, yq_bin)
    elif op == Operation.restore:
        write_inventories(inventories, kpt, yq_bin)
    else:
        die(f"Asked to perform an invalid operation {op}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
