SHELL = /usr/bin/env bash -o pipefail
.SHELLFLAGS = -ec

TOP_DIR := $(abspath $(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
BASE=$(CURDIR)

PLAYGROUND_PREFS_FILE ?= prefs.mk
PG_PREFS_REAL_LOC := $(realpath $(PLAYGROUND_PREFS_FILE))
ifeq ($(PG_PREFS_REAL_LOC),)
$(error "Preferences file $(PLAYGROUND_PREFS_FILE) not found")
endif
-include $(PG_PREFS_REAL_LOC)
-include $(realpath $(TOP_DIR)/private/$(PLAYGROUND_PREFS_FILE))

ifeq ($(USE_ASSET_HOST),1)
include $(realpath $(TOP_DIR)/asset-host.conf.mk)
$(info --> INFO: USE_ASSET_HOST=$(USE_ASSET_HOST) using ASSET_HOST=$(ASSET_HOST))
endif

## Top level options
BUILD ?= build
KIND_CLUSTER_NAME ?= eda-demo
TOPO ?= $(TOP_DIR)/topology/3-nodes-srl.yaml
SIMTOPO ?= $(TOP_DIR)/topology/00-sim-config.yaml
TOPO_EMPTY ?= $(TOP_DIR)/topology/00-delete-all-nodes.yaml
LOGS_DEST ?= /tmp/eda-support/logs-$(shell date +"%Y%m%d%H%M%S")

ifdef MACOS
NO_KIND := 1
NO_LB := 1
$(info --> INFO: MACOS=$(MACOS) - enabling NO_KIND=$(NO_KIND) and NO_LB=$(NO_LB))
endif

ARCH_QUERY := $(shell uname -m)
ifeq ($(ARCH_QUERY), x86_64)
	ARCH := amd64
else ifeq ($(ARCH_QUERY),$(filter $(ARCH_QUERY), arm64 aarch64))
	ARCH := arm64
else
	ARCH := $(ARCH_QUERY)
endif

# i.e Darwin / Linux
UNAME := $(shell uname)
# Lowercase - sane version
OS := $(shell echo "$(UNAME)" | tr '[:upper:]' '[:lower:]')

ifeq ($(OS), darwin)
	XARGS_CMD ?= xargs -S 4096
else
	XARGS_CMD ?= xargs

	EXT_IPV4_ADDR ?= $(shell ip route get 8.8.8.8 2>/dev/null | grep 'src' | sed 's/.*src \([^ ]*\).*/\1/' || echo "")
	EXT_IPV6_ADDR ?= $(shell ip -6 route get 2001:4860:4860::8888 2>/dev/null | grep 'src' | sed 's/.*src \([^ ]*\).*/\1/' || echo "")
endif

OK := [  \e[0;32mOK\033[0m  ]
ERROR := [ \e[0;31mFAIL\033[0m ]

# Top level options

# units: Kb - default output of df
MIN_DISK_SPACE ?= 30000000
FS_NOTIFY_MAX_USER_WATCHES ?= 1048576
FD_NOTIFY_MAX_USER_INSTANCES ?= 512

EDA_CORE_NAMESPACE ?= eda-system
EDA_GOGS_NAMESPACE ?= eda-system
EDA_TRUSTMGR_NAMESPACE ?= eda-system
EDA_USER_NAMESPACE ?= eda
EDA_APPS_INSTALL_NAMESPACE ?= $(EDA_CORE_NAMESPACE)
ENGINECONFIG_CR_NAME ?= engine-config
LB_POOL_NAME ?= kind

EXT_DOMAIN_NAME ?= $(shell hostname -f)
EXT_HTTP_PORT ?= 9200
EXT_HTTPS_PORT ?= 9443

SINGLESTACK_SVCS ?= false
SIMULATE ?= true
HTTPS_PROXY ?= ""
HTTP_PROXY ?= ""
NO_PROXY ?= ""
https_proxy ?= ""
http_proxy ?= ""
no_proxy ?= ""
LLM_API_KEY ?= ""


APPLY_SETTER_IMG ?= ghcr.io/srl-labs/kpt-apply-setters:0.1.1

CORE_IMAGE_REGISTRY=ghcr.io/nokia-eda
SRL_IMAGE_REGISTRY=ghcr.io/nokia
SRL_24_10_1_GHCR=$(SRL_IMAGE_REGISTRY)/srlinux:24.10.1-492


## Level 2 options
TOOLS ?= $(BASE)/tools
KPT_PKG ?= $(BASE)/eda-kpt
CATALOG ?= $(BASE)/catalog
K8S_HELM ?= $(BASE)/connect-k8s-helm-charts
TIMEOUT_NODE_READY ?= 600s

KPT_LIVE_INIT_FORCE ?= 0
KPT_INVENTORY_ADOPT ?= 0

ifeq ($(KPT_INVENTORY_ADOPT),1)
KPT_LIVE_APPLY_ARGS += --inventory-policy=adopt
endif

CFG := $(TOP_DIR)/configs

KIND_CONFIG_FILE ?= $(CFG)/kind.yaml
KIND_CONFIG_REAL_LOC := $(realpath $(KIND_CONFIG_FILE))
ifeq ($(KIND_CONFIG_REAL_LOC),)
$(error "[ERROR] KIND config file $(KIND_CONFIG_REAL_LOC) not found")
endif

KPT_SETTERS_FILE ?= $(CFG)/kpt-setters.yaml
KPT_SETTERS_REAL_LOC := $(realpath $(KPT_SETTERS_FILE))
KPT_SETTERS_WORK_FILE := $(TOP_DIR)/$(BUILD)/kpt-setters.yaml
ifeq ($(KPT_SETTERS_REAL_LOC),)
$(error "[ERROR] KPT setters file '$(KPT_SETTERS_REAL_LOC)' not found")
endif

APPS_INSTALL_CRS ?= $(CATALOG)/install-crs
APPS_VENDOR ?= nokia
APP_INSTALL_TIMEOUT ?= 600
APPS_REGISTRY_NAME ?= eda-apps-registry
APPS_CATALOG_NAME ?= eda-catalog-builtin-apps
APP_INSTALL_MODE ?= BULK
APP_INSTALL_BULK_TEMPLATE ?= $(TOP_DIR)/configs/bulk-app-workflow-template.yaml
APP_INSTALL_BULK_CR ?= $(BUILD)/bulk-app-install-workflow.yaml
APP_INSTALL_BULK_WF_NAME ?= eda-apps-bulk-install

## Print all of the pref files information
$(info --> INFO: Using $(PG_PREFS_REAL_LOC) as the preferences file)
$(info --> INFO: Using $(KIND_CONFIG_REAL_LOC) as the KIND cluster configuration file)
$(info --> INFO: Using $(KPT_SETTERS_REAL_LOC) as the KPT setters file)

KPT_EXT_PKGS := $(KPT_PKG)/eda-external-packages
KPT_CORE := $(KPT_PKG)/eda-kpt-base
KPT_PLAYGROUND := $(KPT_PKG)/eda-kpt-playground

CM_WH_YML := $(KPT_PKG)/eda-external-packages/webhook-tests/cert-manager-webhook-ready-check.yaml

GET_SVC_CIDR=$(KUBECTL) cluster-info dump | grep -m 1 service-cluster-ip-range | sed 's/ //g' | sed -ne 's/\"--service-cluster-ip-range=\(.*\)\",/\1/p'
GET_POD_CIDR=$(KUBECTL) cluster-info dump | grep -m 1 cluster-cidr | sed 's/ //g' | sed -ne 's/\"--cluster-cidr=\(.*\)\",/\1/p'

## Tool Versions:
EDABUILDER_VERSION ?= v1.0.0
GH_VERSION ?= 2.67.0
HELM_VERSION ?= v3.17.0
K9S_VERSION ?= v0.32.5
KIND_VERSION ?= v0.27.0
KPT_VERSION ?= v1.0.0-beta.44
KUBECTL_VERSION ?= v1.31.1
UV_VERSION ?= 0.6.2
YQ_VERSION ?= v4.42.1

## EDA Versions and Decisions
EDA_CORE_VERSION ?= 25.4.1
EDA_APPS_VERSION ?= 25.4.1

### Release specifc options:
### Bulk app install mode is available >= 25.x
### Toplogy loader configMap name is eda-topology >= 25.x else topo-config
ifeq ($(findstring 24.,$(EDA_CORE_VERSION)),24.)
USE_BULK_APP_INSTALL ?= 0
TOPO_CONFIGMAP_NAME ?= topo-config
IS_EDA_CORE_VERSION_24X ?= 1
else
USE_BULK_APP_INSTALL ?= 1
TOPO_CONFIGMAP_NAME ?= eda-topology
IS_EDA_CORE_VERSION_24X ?= 0
endif

ifeq ($(findstring 24.,$(EDA_APPS_VERSION)),24.)
IS_EDA_APPS_VERSION_24X ?= 1
else
IS_EDA_APPS_VERSION_24X ?= 0
endif

## Tools:
GH ?= $(TOOLS)/gh
HELM ?= $(TOOLS)/helm-$(HELM_VERSION)
K9S ?= $(TOOLS)/k9s-$(K9S_VERSION)
KIND ?= $(TOOLS)/kind-$(KIND_VERSION)
KPT ?= $(TOOLS)/kpt-$(KPT_VERSION)
KUBECTL ?= $(TOOLS)/kubectl-$(KUBECTL_VERSION)
UV ?= $(TOOLS)/uv
YQ ?= $(TOOLS)/yq-$(YQ_VERSION)

## Curl options:
CURL := curl --silent --fail --show-error

SED ?= sed

INDENT_OUT := $(SED) 's/^/    /'
INDENT_OUT_ERROR := $(SED) 's/^/        /'

## Where to get things:

### Access tokens

# Clone the repos to be used by the playground Makefile
GH_RO_TOKEN ?=
# Tokens to set in the kpt package for the AppStore Controller to pull the catalog and app images
GH_PKG_TOKEN ?= RURBZ2hwXzRxcGpPanJ1eVJXa3Zzc0NGcUdENUFlZ29VN3dXYTN4c0NKSgo=
GH_REG_TOKEN ?= RURBZ2hwXzRxcGpPanJ1eVJXa3Zzc0NGcUdENUFlZ29VN3dXYTN4c0NKSgo=

GH_KPT_URL ?= github.com/nokia-eda/kpt.git
GH_CAT_URL ?= github.com/nokia-eda/catalog.git
GH_K8s_HELM_URL ?= github.com/nokia-eda/connect-k8s-helm-charts.git

### EDA Components
ifeq ($(GH_RO_TOKEN),)
EDA_KPT_PKG_SRC ?= https://$(GH_KPT_URL)
CATALOG_PKG_SRC ?= https://$(GH_CAT_URL)
K8S_HELM_PKG_SRC ?= https://$(GH_K8s_HELM_URL)
else
EDA_KPT_PKG_SRC ?= https://$(GH_RO_TOKEN)@$(GH_KPT_URL)
CATALOG_PKG_SRC ?= https://$(GH_RO_TOKEN)@$(GH_CAT_URL)
K8S_HELM_PKG_SRC ?= https://$(GH_RO_TOKEN)@$(GH_K8s_HELM_URL)
endif

### Tools
KIND_SRC ?= https://kind.sigs.k8s.io/dl/$(KIND_VERSION)/kind-$(OS)-$(ARCH)
KUBECTL_SRC ?= https://dl.k8s.io/release/$(KUBECTL_VERSION)/bin/$(OS)/$(ARCH)/kubectl
HELM_SRC ?= https://get.helm.sh/helm-$(HELM_VERSION)-$(OS)-$(ARCH).tar.gz
KPT_SRC ?= https://github.com/GoogleContainerTools/kpt/releases/download/$(KPT_VERSION)/kpt_$(OS)_$(ARCH)
# K9s uses the uname directly in its package name
K9S_SRC ?= https://github.com/derailed/k9s/releases/download/$(K9S_VERSION)/k9s_$(UNAME)_$(ARCH).tar.gz
YQ_SRC ?= https://github.com/mikefarah/yq/releases/download/$(YQ_VERSION)/yq_$(OS)_$(ARCH)
EDABUILDER_SRC ?= nokia-eda/edabuilder

## Create working directories

$(BUILD): | $(BASE); $(info --> INFO: Creating a build dir: $(BUILD))
	@mkdir -p $(BUILD)

$(TOOLS): | $(BASE); $(info --> INFO: Creating a tools dir: $(TOOLS))
	@mkdir -p $(TOOLS)

## Download tools

DOWNLOAD_TOOLS_LIST=
DOWNLOAD_TOOLS_LIST += $(HELM)
DOWNLOAD_TOOLS_LIST += $(KIND)
DOWNLOAD_TOOLS_LIST += $(KPT)
DOWNLOAD_TOOLS_LIST += $(KUBECTL)
DOWNLOAD_TOOLS_LIST += $(YQ)

ifneq ($(USE_ASSET_HOST),1)
DOWNLOAD_TOOLS_LIST += $(GH)
DOWNLOAD_TOOLS_LIST += $(UV)
endif

.PHONY: download-tools
download-tools: | $(BASE) $(DOWNLOAD_TOOLS_LIST) ## Download required tools

.PHONY: download-k9s
download-k9s: | $(BASE) $(K9S) ## Download k9s

.PHONY: download-edabuilder
download-edabuilder: | $(BASE) $(GH) ## Download edabuilder
	@$(GH) release download $(EDABUILDER_VERSION) --repo $(EDABUILDER_SRC) --pattern "edabuilder-$(EDABUILDER_VERSION)-$(OS)-$(ARCH)" --skip-existing -O $(TOOLS)/edabuilder
	@chmod a+x $(TOOLS)/edabuilder

define download-bin
    $(info --> INFO: Downloading $(2))
	if test ! -f $(1); then $(CURL) -Lo $(1) $(2) >/dev/null && chmod a+x $(1); fi
endef

# $1 - Output binary name to extract from the archive
# $2 - URL to download it from
# $3 - where should tar extract this file ?
# $4 - What is the path/filename inside the archive ?
# $5 - tar options if its compressed etc
# $6 - number of path components to strip (optional)
# This does assume that $(1) on disk is equal to $(3)/$(4) where $(4) is the path+name of the bin inside the archive
define download-bin-from-archive
	if test ! -f $(1); then $(CURL) -L --output - $(2) | tar -x$(5) $(if $(6),--strip-components=$(6),) --to-stdout -C $(3) $(4) > $(1) && chmod +x $(1); fi
endef

$(KIND): | $(BASE) $(TOOLS) ; $(info --> TOOLS: Ensuring kind is present in $(KIND))
	@$(call download-bin,$(KIND),$(KIND_SRC))

$(KUBECTL): | $(BASE) $(TOOLS) ; $(info --> TOOLS: Ensuring kubectl is present in $(KUBECTL))
	@$(call download-bin,$(KUBECTL),$(KUBECTL_SRC))

$(HELM): | $(BASE) $(TOOLS) ; $(info --> TOOLS: Ensuring helm is present in $(HELM))
	@$(call download-bin-from-archive,$(HELM),$(HELM_SRC),$(TOOLS),${OS}-${ARCH}/helm,z,1)

$(KPT): | $(BASE) $(TOOLS) ; $(info --> TOOLS: Ensuring kpt is present in $(KPT))
	@$(call download-bin,$(KPT),$(KPT_SRC))

$(K9S): | $(BASE) $(TOOLS) ; $(info --> TOOLS: Ensuring k9s is present in $(K9S))
	@$(call download-bin-from-archive,$(K9S),$(K9S_SRC),$(TOOLS),k9s,z)

$(YQ): | $(BASE) $(TOOLS) ; $(info --> TOOLS: Ensuring yq is present in $(YQ))
	@$(call download-bin,$(YQ),$(YQ_SRC))

$(GH): | $(BASE) $(TOOLS) ; $(info --> TOOLS: Ensuring gh is present in $(GH))
	@{ \
		OS="$(OS)"; \
		EXT="tar.gz"; \
		if [ "$(OS)" = "darwin" ]; then \
			OS="macOS"; \
			EXT="zip"; \
		fi; \
		GH_SRC="https://github.com/cli/cli/releases/download/v$(GH_VERSION)/gh_$(GH_VERSION)_$${OS}_$(ARCH).$${EXT}"; \
		$(call download-bin-from-archive,$(GH),$${GH_SRC},$(TOOLS),gh_$(GH_VERSION)_$${OS}_$(ARCH)/bin/gh,z,2); \
	}

$(UV): | $(BASE) $(TOOLS) ; $(info --> TOOLS: Ensuring uv is present in $(UV))
	@{ \
		if [ "$(ARCH)" = "arm64" ]; then \
			ARCH="aarch64"; \
		elif [ "$(ARCH)" = "amd64" ]; then \
			ARCH="x86_64"; \
		fi; \
		if [ "$(OS)" = "darwin" ]; then \
			OS="apple-darwin"; \
		elif [ "$(OS)" = "linux" ]; then \
			OS="unknown-linux-gnu"; \
		fi; \
		UV_SRC="https://github.com/astral-sh/uv/releases/download/$(UV_VERSION)/uv-$${ARCH}-$${OS}.tar.gz"; \
		$(call download-bin-from-archive,$(UV),$$UV_SRC,$(TOOLS),uv-$${ARCH}-$${OS},z,1); \
	}

## Download the kpt package and the catalog
$(KPT_PKG): | $(BASE) $(KPT) ; $(info --> KPT: Ensuring the kpt pkg is present in $(KPT_PKG))
#	$(KPT) pkg get $(EDA_KPT_PKG_SRC) $(KPT_PKG)
	git clone $(EDA_KPT_PKG_SRC) $(KPT_PKG) 2>&1 | sed 's/^/    /'

$(CATALOG): | $(BASE); $(info --> APPS: Ensuring the apps catalog is present in $(CATALOG))
	git clone $(CATALOG_PKG_SRC) $(CATALOG) 2>&1 | sed 's/^/    /'

.PHONY: download-pkgs
download-pkgs: | $(KPT_PKG) $(CATALOG) ## Download the eda-kpt and apps catalog 

# $1 - tag to checkout
# $2 - Location of the repo
define checkout-repo-at-tag
{	\
	VERSION=$(1)																		;\
	REPO=$(2)																			;\
	echo "--> INFO: $${REPO} - selected version: $${VERSION}"							;\
	git -C $${REPO} fetch 2>&1 | $(INDENT_OUT)											;\
	tag="v$${VERSION}"																	;\
	HEAD=$$(git -C $${REPO} rev-parse HEAD)												;\
	if [[ "$$(git -C $${REPO} tag -l $${tag})" == "" ]]; then							 \
		echo ""																			;\
		echo "[ERROR]: $${VERSION} does not exist in $${REPO}"							;\
		echo "         Do you need to run make update-pkgs ?"							;\
		exit 1																			;\
	fi																					;\
	TAG_REF=$$(git -C $${REPO} rev-parse $${tag})										;\
	if [[ "$${TAG_REF}" == "$${HEAD}" ]]; then											 \
		echo "--> INFO: $${REPO} - is at $${VERSION}"									;\
		exit 0																			;\
	fi																					;\
	if [[ "$$(git -C $${REPO} status --porcelain --untracked-files=no)" != "" ]]		;\
	then																				 \
		echo ""																			;\
		echo "[ERROR]: There are user customizations present in $${REPO}"				;\
		echo "         Please reset or stash: 'git -C $${REPO} stash'"					;\
		exit 1																			;\
	fi																					;\
	git -C $${REPO} -c advice.detachedHead=false checkout $${tag} 2>&1 | $(INDENT_OUT)	;\
	echo "--> INFO: $${REPO} - is now at $$(git -C $${REPO} tag --points-at HEAD)"		;\
}
endef

.PHONY: update-pkgs
update-pkgs: | $(KPT_PKG) $(CATALOG) ## Fetch eda kpt and catalog updates
	@echo "--> INFO: Updating $(KPT_PKG)"
	@git -C $(KPT_PKG) fetch 2>&1 | $(INDENT_OUT)
	@echo "--> INFO: Updating $(CATALOG)"
	@git -C $(CATALOG) fetch 2>&1 | $(INDENT_OUT)
	@git -C $(CATALOG) fetch --tags --force --all 2>&1 | $(INDENT_OUT)
	@$(call checkout-repo-at-tag,$(EDA_CORE_VERSION),$(KPT_PKG))
	@$(call checkout-repo-at-tag,$(EDA_APPS_VERSION),$(CATALOG))

$(K8S_HELM): | $(BASE); $(info --> CONNECT K8S HELM CHARTS: Ensuring the Connect K8s Helm charts are present in $(K8S_HELM))
	git clone $(K8S_HELM_PKG_SRC) $(K8S_HELM) 2>&1 | $(INDENT_OUT)

.PHONY: download-connect-k8s-helm-charts
download-connect-k8s-helm-charts: | $(K8S_HELM) ## Download the connect-k8s-helm-charts

.PHONY: update-connect-k8s-helm-charts
update-connect-k8s-helm-charts: | $(K8S_HELM) ## Fetch connect-k8s-helm-charts updates
	git -C $(K8S_HELM) pull

## Cluster launch

.PHONY: kind
kind: cluster cluster-wait-for-node-ready ## Launch a single node KinD cluster (K8S inside Docker)

.PHONY: cluster
cluster: | $(BUILD) $(KIND) $(KUBECTL) ; $(info --> KIND: Ensuring control-plane exists)
	@{	\
		cp $(KIND_CONFIG_REAL_LOC) $(BUILD)/kind.yaml; \
		if [ ! -z "$(KIND_API_SERVER_ADDRESS)" ]; then \
			$(YQ) eval ".networking.apiServerAddress = \"$(KIND_API_SERVER_ADDRESS)\"" -i $(BUILD)/kind.yaml; \
		fi; \
		MATCHED=0																			;\
		for cluster in $$($(KIND) get clusters); do 										 \
			if [[ "$${cluster}" == "$(KIND_CLUSTER_NAME)" ]]; then							 \
				MATCHED=1																	;\
			fi																				;\
		done																				;\
		if [[ "$${MATCHED}" == "0" ]]; then													 \
			$(KIND) create cluster --name $(KIND_CLUSTER_NAME)	--config $(BUILD)/kind.yaml 2>&1 | sed 's/^/    /' ;\
		else																				 \
			echo "--> KIND: cluster named $(KIND_CLUSTER_NAME) exists"						;\
		fi																					;\
	}

.PHONY: cluster-wait-for-node-ready
cluster-wait-for-node-ready: | $(BASE) ; $(info --> KIND: wait for k8s node to be ready) @ ## Wait for the k8s cp to declare the node to be ready
	@{	\
		START=$$(date +%s)																;\
		$(KUBECTL) wait --for=condition=Ready nodes --all --timeout=$(TIMEOUT_NODE_READY) 2>&1 | sed 's/^/    /' ;\
		echo "--> KIND: Node ready check took $$(( $$(date +%s) - $$START ))s" ;\
	}

define is_ipv6
$(shell echo $(1) | grep -q ":" && echo 1 || echo 0)
endef


# Iterating over subnets and assigning them to respective variables
define process_subnet
$(eval IPV6_CHECK := $(call is_ipv6,$(1)))
ifeq ($(IPV6_CHECK),1)
	KIND_SUBNET6 := $(shell echo $(1) | awk -F: '{{print $$1 ":" $$2 ":" $$3 ":" $$4}}')
else
	KIND_SUBNET := $(shell echo $(1) | awk -F. '{{print $$1 "." $$2}}')
endif
endef


.PHONY: metallb-operator
metallb-operator: | $(BASE) $(BUILD) $(KUBECTL) ; $(info --> LB: Loading the load balancer, metallb in the cluster)
	@{	\
		$(KUBECTL) apply -f $(CFG)/metallb-native.yaml | sed 's/^/    /';\
		$(KUBECTL) wait --namespace metallb-system \
						--for=condition=ready pod \
						--selector=app=metallb \
						--timeout=120s | sed 's/^/    /';\
	}

LB_CFG_SRC_ANNOUNCE ?= $(CFG)/metallb-config-L2Advertisement.yaml
LB_CFG_SRC_POOL ?= $(CFG)/metallb-config-defaultPool.yaml
KIND_BRIDGE_NAME ?= kind

.PHONY: metallb-configure-pools
metallb-configure-pools: | $(BASE) $(KPT) ; $(info --> LB: Applying metallb IP pool configuration) @ ## Create metallb address pools
ifdef NO_KIND
	@if [[ -z "$(METALLB_VIP)" ]]; then echo "[ERROR] METALLB_VIP is not specified" && exit 1; fi;
	@echo "--> LB: NO_KIND=$(NO_KIND) specified - using $(METALLB_VIP)"
	@cat $(LB_CFG_SRC_POOL) | $(KPT) fn eval - --image $(APPLY_SETTER_IMG) --truncate-output=false --output unwrap -- LB_IP_POOLS="[$(METALLB_VIP)]" LB_POOL_NAME=$(LB_POOL_NAME) | $(KUBECTL) apply -f - | sed 's/^/    /'
else
	$(eval KIND_SUBNETS=$(shell docker network inspect -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}' $(KIND_BRIDGE_NAME)))
	$(eval KIND_SUBNET=$(shell echo "$(KIND_SUBNETS)" | tr ' ' '\n' | grep -v ':' | head -n 1 | awk -F'.' '{print $$1 "." $$2}'))
	$(eval KIND_SUBNET6=$(shell echo "$(KIND_SUBNETS)" | tr ' ' '\n' | grep ':' | head -n 1 | awk -F':' '{print $$1 ":" $$2 ":" $$3 ":" $$4}'))
	@echo "--> LB: Detected IPv4 Subnet: $(KIND_SUBNET)"
	@echo "--> LB: Detected IPv6 Subnet: $(KIND_SUBNET6)"
	@cat $(LB_CFG_SRC_POOL) | $(KPT) fn eval - --image $(APPLY_SETTER_IMG) --truncate-output=false --output unwrap -- LB_IP_POOLS="[$(KIND_SUBNET).255.0/24, $(KIND_SUBNET6):ffff:ffff:ffff:ffff/120]" LB_POOL_NAME=$(LB_POOL_NAME) | $(KUBECTL) apply -f - | sed 's/^/    /'
endif

.PHONY: metallb-configure-speaker
metallb-configure-speaker: | $(BASE) $(KPT) ; $(info --> LB: Applying metallb L2 speaker config) @ ## Apply metallb L2 announcement speaker configuration
	@cat $(LB_CFG_SRC_ANNOUNCE) | $(KUBECTL) apply -f - | sed 's/^/    /'

.PHONY: metallb-configure
metallb-configure: | $(BASE) metallb-configure-pools metallb-configure-speaker ; $(info --> LB: Applying metallb configuration) @ ## Apply metallb controller + speaker configuration

.PHONY: metallb
metallb: | $(BASE) $(KUBECTL) metallb-operator metallb-configure ## Load the metallb loadbalancer into the cluster

.PHONY: cm-is-deployment-ready
cm-is-deployment-ready: | $(BASE) $(KUBECTL) ; $(info --> CERT: Waiting for deployment to be ready) @ ## Is the deployment ready ?
	@{	\
		START=$$(date +%s);\
		$(KUBECTL) wait deployment cert-manager-webhook -n cert-manager --for condition=Available=True --timeout=120s 2>&1 | sed 's/^/    /';\
		echo "--> CERT: Deployment is ready - took: $$(( $$(date +%s) - $$START ))s" ;\
	}

.PHONY: cm-is-webhook-ready
cm-is-webhook-ready: ## Is the webhook admissions controller for cert-manager ready ?
	@{	\
		START=$$(date +%s)													;\
		MAX_WAIT=120														;\
		COUNT=0																;\
		INSTALLED=0															;\
		while [ $$COUNT -lt $$MAX_WAIT ]; do								 \
			wh_ready=0														;\
			$(KUBECTL) apply -f $(CM_WH_YML) --dry-run=server || $$wh_ready=$$? ;\
			if [[ $${wh_ready} -eq 0 ]]; then								 \
				INSTALLED=1													;\
				break														;\
			fi																;\
			echo "--> CERT: Waiting for webhook to be ready - $$(date) - count $$COUNT";\
			COUNT=$$((COUNT + 1))											;\
			sleep 1 														;\
		done 																;\
		if [ $$INSTALLED -ne 1 ] ; then										 \
			echo "--> CERT: Webhook is not ready in $${COUNT}s"				;\
			exit 1 															;\
		else																 \
			echo "--> CERT: Webhook is ready - took: $$(( $$(date +%s) - $$START ))s" ;\
		fi																	;\
	}

.PHONY: trustmgr-is-deployment-ready
trustmgr-is-deployment-ready: | $(BASE) $(KUBECTL); $(info --> TRUST: Waiting for deployment to be ready) @ ## Is the deployment up ?
	@{	\
		START=$$(date +%s)																											;\
		$(KUBECTL) wait deployment trust-manager -n $(EDA_TRUSTMGR_NAMESPACE) --for condition=Available=True --timeout=120s 2>&1 | sed 's/^/    /'	;\
		echo "--> TRUST: Deployment is ready - took: $$(( $$(date +%s) - $$START ))s" 												;\
	}

POD_SELECTOR_GOGS ?= git
POD_LABEL_GOGS ?= eda.nokia.com/app=$(POD_SELECTOR_GOGS)

.PHONY: git-is-init-done
git-is-init-done: | $(BASE) $(KUBECTL) ; $(info --> GOGS: Waiting for pod init to complete) @ ## Has the gogs pod done launching ? Halt till then
	@$(KUBECTL) -n $(EDA_GOGS_NAMESPACE) exec -it $$($(KUBECTL) -n $(EDA_GOGS_NAMESPACE) get pods -l eda.nokia.com/app=$(POD_SELECTOR_GOGS) --no-headers -o=jsonpath='{.items[*].metadata.name}') -- bash -c 'until [[ -f /data/eda-git-init.done ]]; do echo "--> GOGS: waiting for init.done ... - $$(date)" && sleep 1; done; echo "--> GOGS: Reached init.done!"'

## The @ suppressor is not here, its in the $(call ...) where the macro is called
define INSTALL_KPT_PACKAGE
	{	\
		echo -e "--> INSTALL: [\033[1;34m$2\033[0m] - Applying kpt package"									;\
		pushd $1 &>/dev/null || (echo "[ERROR]: Failed to switch cwd to $2" && exit 1)						;\
		if [[ ! -f resourcegroup.yaml ]] || [[ $(KPT_LIVE_INIT_FORCE) -eq 1 ]]; then						 \
			$(KPT) live init --force 2>&1 | sed 's/^/    /'													;\
		else																								 \
			echo -e "--> INSTALL: [\033[1;34m$2\033[0m] - Resource group found, don't re-init this package"	;\
		fi																									;\
		$(KPT) live apply $(KPT_LIVE_APPLY_ARGS) 2>&1 | sed 's/^/    /'										;\
		popd &>/dev/null || (echo "[ERROR]: Failed to switch back from $2" && exit 1)						;\
		echo -e "--> INSTALL: [\033[0;32m$2\033[0m] - Applied and reconciled package"						;\
	}
endef

.PHONY: load-image-pull-secret
load-image-pull-secret: | $(BASE) $(KUBECTL) $(KPT_PKG)
	@$(KUBECTL) -n $(EDA_CORE_NAMESPACE) apply -f $(TOP_DIR)/eda-kpt/eda-kpt-base/secrets/gh-core-pkgs.yaml 2>&1 | sed 's/^/    /'

.PHONY: install-eda-core-ns
install-eda-core-ns: | $(BASE) $(KPT) 
	@$(call INSTALL_KPT_PACKAGE,$(KPT_EXT_PKGS)/eda-core-ns,core-ns)

.PHONY: install-external-package-fluentd
install-external-package-fluentd: | $(BASE) $(KPT) load-image-pull-secret
	@$(call INSTALL_KPT_PACKAGE,$(KPT_EXT_PKGS)/fluentd,fluentd)

.PHONY: install-external-package-cert-manager
install-external-package-cert-manager: | $(BASE) $(KPT) load-image-pull-secret
	@$(call INSTALL_KPT_PACKAGE,$(KPT_EXT_PKGS)/cert-manager,cert-manager)

.PHONY: install-external-package-csi-driver
install-external-package-csi-driver: | $(BASE) $(KPT) load-image-pull-secret
	@$(call INSTALL_KPT_PACKAGE,$(KPT_EXT_PKGS)/csi-driver,csi-driver)

.PHONY: install-external-package-trust-manager
install-external-package-trust-manager: | $(BASE) $(KPT) load-image-pull-secret
	@$(call INSTALL_KPT_PACKAGE,$(KPT_EXT_PKGS)/trust-manager,trust-manager)

.PHONY: install-external-package-git
install-external-package-git: | $(BASE) $(KPT) load-image-pull-secret
	@$(call INSTALL_KPT_PACKAGE,$(KPT_EXT_PKGS)/git,git)

.PHONY: install-external-package-eda-issuer-root
install-external-package-eda-issuer-root: | $(BASE) $(KPT) load-image-pull-secret
	@$(call INSTALL_KPT_PACKAGE,$(KPT_EXT_PKGS)/eda-issuer-root,eda root issuer)

.PHONY: install-external-package-eda-issuer-node
install-external-package-eda-issuer-node: | $(BASE) $(KPT) load-image-pull-secret
	@$(call INSTALL_KPT_PACKAGE,$(KPT_EXT_PKGS)/eda-issuer-node,eda node issuer)

.PHONY: install-external-package-eda-issuer-api
install-external-package-eda-issuer-api: | $(BASE) $(KPT) load-image-pull-secret
	@$(call INSTALL_KPT_PACKAGE,$(KPT_EXT_PKGS)/eda-issuer-api,eda api issuer)

INSTALL_EXTERNAL_PACKAGE_LIST=
INSTALL_EXTERNAL_PACKAGE_LIST += install-eda-core-ns
INSTALL_EXTERNAL_PACKAGE_LIST += load-image-pull-secret
INSTALL_EXTERNAL_PACKAGE_LIST += install-external-package-fluentd
INSTALL_EXTERNAL_PACKAGE_LIST += $(if $(NO_CERT_MANAGER_INSTALL),,install-external-package-cert-manager)
INSTALL_EXTERNAL_PACKAGE_LIST += cm-is-deployment-ready
INSTALL_EXTERNAL_PACKAGE_LIST += cm-is-webhook-ready
INSTALL_EXTERNAL_PACKAGE_LIST += install-external-package-csi-driver
INSTALL_EXTERNAL_PACKAGE_LIST += install-external-package-trust-manager
INSTALL_EXTERNAL_PACKAGE_LIST += trustmgr-is-deployment-ready
INSTALL_EXTERNAL_PACKAGE_LIST += install-external-package-git
INSTALL_EXTERNAL_PACKAGE_LIST += git-is-init-done
INSTALL_EXTERNAL_PACKAGE_LIST += install-external-package-eda-issuer-root
INSTALL_EXTERNAL_PACKAGE_LIST += install-external-package-eda-issuer-node
INSTALL_EXTERNAL_PACKAGE_LIST += install-external-package-eda-issuer-api

.PHONY: install-external-packages
install-external-packages: | $(BASE) configure-external-packages $(INSTALL_EXTERNAL_PACKAGE_LIST) ## Install external components for EDA core (cert/trust-manager, fluentd, csi, gogs, CA's)


.PHONY: instantiate-kpt-setters-work-file
instantiate-kpt-setters-work-file: | $(BASE) $(BUILD) $(CFG) $(YQ) ## Instantiate kpt setters work file from a template and set the known values
	@{	\
		if [ ! -f $(KPT_SETTERS_WORK_FILE) ] || [ $(KPT_SETTERS_REAL_LOC) -nt $(KPT_SETTERS_WORK_FILE) ]; then \
			cp -v $(KPT_SETTERS_REAL_LOC) $(KPT_SETTERS_WORK_FILE);\
		fi; \
		$(YQ) eval --no-doc '... comments=""' -i $(KPT_SETTERS_WORK_FILE);\
		export cluster_pod_cidr=$$($(GET_POD_CIDR))				;\
		export cluster_svc_cidr=$$($(GET_SVC_CIDR))				;\
		export HTTPS_PROXY=$(HTTPS_PROXY)						;\
		export HTTP_PROXY=$(HTTP_PROXY)							;\
		export NO_PROXY="$(NO_PROXY),$${cluster_pod_cidr},$${cluster_svc_cidr},.local,.svc,eda-git,eda-git-replica";\
		export https_proxy=$(https_proxy)						;\
		export http_proxy=$(http_proxy)							;\
		export no_proxy="$(no_proxy),$${cluster_pod_cidr},$${cluster_svc_cidr},.local,.svc,eda-git,eda-git-replica";\
		export RO_TOKEN_REG=$$(echo "$(GH_REG_TOKEN)" | base64 -d | cut -c 4- | base64)	;\
		export RO_TOKEN_CATALOG=$$(echo "$(GH_PKG_TOKEN)" | base64 -d | cut -c 4- | base64)	;\
		$(YQ) eval --no-doc '... comments=""' -i $(KPT_SETTERS_WORK_FILE);\
		$(YQ) eval ".data.SINGLESTACK_SVCS = \"$(SINGLESTACK_SVCS)\"" -i $(KPT_SETTERS_WORK_FILE); \
		$(YQ) eval ".data.SIMULATE = \"$(SIMULATE)\"" -i $(KPT_SETTERS_WORK_FILE); \
		$(YQ) eval ".data.LLM_API_KEY = \"$(LLM_API_KEY)\"" -i $(KPT_SETTERS_WORK_FILE); \
		$(YQ) eval ".data.EXT_DOMAIN_NAME = \"$(EXT_DOMAIN_NAME)\"" -i $(KPT_SETTERS_WORK_FILE); \
		$(YQ) eval ".data.EXT_HTTP_PORT = \"$(EXT_HTTP_PORT)\"" -i $(KPT_SETTERS_WORK_FILE); \
		$(YQ) eval ".data.EXT_HTTPS_PORT = \"$(EXT_HTTPS_PORT)\"" -i $(KPT_SETTERS_WORK_FILE); \
		$(YQ) eval ".data.EXT_IPV4_ADDR = \"$(EXT_IPV4_ADDR)\"" -i $(KPT_SETTERS_WORK_FILE); \
		$(YQ) eval ".data.EXT_IPV6_ADDR = \"$(EXT_IPV6_ADDR)\"" -i $(KPT_SETTERS_WORK_FILE); \
		$(YQ) eval ".data.HTTPS_PROXY = \"$${HTTPS_PROXY}\"" -i $(KPT_SETTERS_WORK_FILE); \
		$(YQ) eval ".data.HTTP_PROXY = \"$${HTTP_PROXY}\"" -i $(KPT_SETTERS_WORK_FILE); \
		$(YQ) eval ".data.NO_PROXY = \"$${NO_PROXY}\"" -i $(KPT_SETTERS_WORK_FILE); \
		$(YQ) eval ".data.https_proxy = \"$${https_proxy}\"" -i $(KPT_SETTERS_WORK_FILE); \
		$(YQ) eval ".data.http_proxy = \"$${http_proxy}\"" -i $(KPT_SETTERS_WORK_FILE); \
		$(YQ) eval ".data.no_proxy = \"$${no_proxy}\"" -i $(KPT_SETTERS_WORK_FILE); \
		$(YQ) eval ".data.SRL_24_10_1_GHCR = \"$(SRL_24_10_1_GHCR)\"" -i $(KPT_SETTERS_WORK_FILE); \
		$(YQ) eval ".data.GH_REGISTRY_TOKEN = \"$${RO_TOKEN_REG}\"" -i $(KPT_SETTERS_WORK_FILE); \
		$(YQ) eval ".data.GH_CATALOG_TOKEN = \"$${RO_TOKEN_CATALOG}\"" -i $(KPT_SETTERS_WORK_FILE); \
	}
	@{	\
		export NO_LB="$(NO_LB)"																					;\
		export ENABLE_NODE_PORTS="false"																		;\
		if [[ ! -z "$${NO_LB}" ]] && [[ "$${NO_LB}" != "0" ]]; then												 \
			export ENABLE_NODE_PORTS="true"																		;\
		fi																										;\
		$(YQ) eval ".data.API_SVC_ENABLE_LB_NODE_PORTS = env(ENABLE_NODE_PORTS)" -i $(KPT_SETTERS_WORK_FILE)	;\
	}
# For the non-self-host case, the user must use the configs/kpt-setters.yaml file for any options
ifeq ($(USE_ASSET_HOST),1)
	@{	\
		$(YQ) eval ".data.APP_REGISTRY_SKIPTLSVERIFY = \"$(APP_REGISTRY_SKIPTLSVERIFY)\"" -i $(KPT_SETTERS_WORK_FILE); \
		$(YQ) eval ".data.APP_REGISTRY_MIRROR = \"$(APP_REGISTRY_MIRROR)\"" -i $(KPT_SETTERS_WORK_FILE); \
		$(YQ) eval ".data.APP_CATALOG = \"$(APP_CATALOG)\"" -i $(KPT_SETTERS_WORK_FILE); \
		$(YQ) eval ".data.GH_CATALOG_TOKEN = \"$(GH_CATALOG_TOKEN)\"" -i $(KPT_SETTERS_WORK_FILE); \
		$(YQ) eval ".data.GH_CATALOG_USER = \"$(GH_CATALOG_USER)\"" -i $(KPT_SETTERS_WORK_FILE); \
		$(YQ) eval ".data.YANG_REMOTE_URL = \"$(YANG_REMOTE_URL)\"" -i $(KPT_SETTERS_WORK_FILE); \
		$(YQ) eval ".data.LLM_DB_REMOTE_URL = \"$(LLM_DB_REMOTE_URL)\"" -i $(KPT_SETTERS_WORK_FILE); \
	}
endif


.PHONY: configure-external-packages
configure-external-packages: | $(BASE) $(BUILD) $(KPT) instantiate-kpt-setters-work-file $(if $(filter arm64,$(ARCH)),kpt-set-ext-arm-images,) ## Configure external packages (cert/trust-manager, fluentd, csi, gogs)
	@{	\
		echo "--> KPT:EXT: Configuring external packages"	;\
		pushd $(KPT_EXT_PKGS) &> /dev/null || (echo "[ERROR] Could not change cwd to $(KPT_EXT_PKGS) from $$(pwd)" && exit 1);\
		$(KPT) fn eval --image $(APPLY_SETTER_IMG) \
		--truncate-output=false \
		--fn-config $(KPT_SETTERS_WORK_FILE) 2>&1 | sed 's/^/    /' ;\
		popd &> /dev/null || (echo "[ERROR] Could not change cwd to $(KPT_EXT_PKGS) from $$(pwd)" && exit 1);\
	}

.PHONY: check-ext-access-vars
check-ext-access-vars: ## Check if variables for external access are set
ifeq ($(EXT_DOMAIN_NAME),)
	$(error "EXT_DOMAIN_NAME variable was not set or correctly auto-derived. See https://docs.eda.dev/getting-started/installation-process/#configure-your-deployment for details")
endif

ifeq ($(EXT_HTTPS_PORT),)
	$(error "EXT_HTTPS_PORT variable was not set or correctly auto-derived. See https://docs.eda.dev/getting-started/installation-process/#configure-your-deployment for details")
endif

ifeq ($(EXT_HTTP_PORT),)
	$(error "EXT_HTTP_PORT variable was not set or correctly auto-derived. See https://docs.eda.dev/getting-started/installation-process/#configure-your-deployment for details")
endif

ifeq ($(strip $(EXT_IPV4_ADDR)$(EXT_IPV6_ADDR)),)
	$(error "Either EXT_IPV4_ADDR or EXT_IPV6_ADDR variable must be set. See https://docs.eda.dev/getting-started/installation-process/#configure-your-deployment for details")
endif

.PHONY: eda-configure-core
eda-configure-core: | $(BUILD) $(CFG) instantiate-kpt-setters-work-file check-ext-access-vars ## Configure the EDA core deployment before launching
	@{	\
		echo "--> KPT:CORE: Configuring the core package"	;\
		pushd $(KPT_CORE) &> /dev/null || (echo "[ERROR] Could not change cwd to $(KPT_CORE) from $$(pwd)" && exit 1);\
		$(KPT) fn eval --image $(APPLY_SETTER_IMG) \
		--truncate-output=false \
		--fn-config $(KPT_SETTERS_WORK_FILE) 2>&1 | sed 's/^/    /' ;\
		popd &> /dev/null || (echo "[ERROR] Could not change cwd to $(KPT_CORE) from $$(pwd)" && exit 1);\
	}

.PHONY: eda-install-core
eda-install-core: | $(BASE) $(KPT) ; $(info --> KPT: Launching EDA) @ ## Base install of EDA in a cluster
	@echo "--> INFO: EDA_CORE_VERSION=$(EDA_CORE_VERSION)"
	@$(call INSTALL_KPT_PACKAGE,$(KPT_CORE),EDA CORE)

.PHONY: is-ce-first-commit-done
is-ce-first-commit-done: | $(BASE) $(KUBECTL); $(info --> CE: Blocking until engine has first commit) @ ## Block until the config engine has processed its first commit
	@{	\
		counter=0																											;\
		while true; do																										 \
			if [[ "$$($(KUBECTL) --namespace $(EDA_CORE_NAMESPACE) get engineconfig $(ENGINECONFIG_CR_NAME) -o=jsonpath='{.status.run-status}')" = "Started" ]]; then	 \
				echo "--> CE: Engine first commit complete" && break														;\
			elif [[ $$counter -gt 600 ]]; then																				 \
				$(MAKE) -C $(TOP_DIR) ls-pods ce-logs ce-status																;\
				echo "--> CE: [ERROR] First commit has not reached in 10 mins ($$counter)"									;\
				exit 1																										;\
			else																											 \
				echo "--> CE: Still waiting for first commit... sleeping $$(date +%H:%m:%S) - count $$counter" && sleep 1	;\
			fi																												;\
			((counter+=1))																									;\
		done																												;\
	}

define WAIT_FOR_DEP
	{	\
		START=$$(date +%s)													;\
		INFO_1=0															;\
		INFO_2=0															;\
		while true; do														 \
			if ! $(KUBECTL) --namespace $(EDA_CORE_NAMESPACE) get deployments.apps $1 --no-headers &> /dev/null ; then \
				if [[ $${INFO_1} -ne 1 ]]; then 							 \
					echo -e "--> LAUNCH: [\033[1;35m$1\033[0m] Waiting for deployment to be created";\
					INFO_1=1												;\
				fi															;\
				sleep 2													;\
			else															 \
				avail_rep=$$($(KUBECTL) --namespace $(EDA_CORE_NAMESPACE) get deployments.apps $1 -ojsonpath='{.status.availableReplicas}')	;\
				if [[ $${avail_rep} -eq 1 ]]; then							 \
					echo -e "--> LAUNCH: [\033[0;32m$1\033[0m] deployment is now available - took $$(( $$(date +%s) - $$START ))s"	;\
					break													;\
				else														 \
					if [[ $${INFO_2} -ne 1 ]]; then							 \
						echo -e "--> LAUNCH: [\033[1;34m$1\033[0m] Waiting for deployment to be ready";\
						INFO_2=1											;\
					fi														;\
					sleep 2												;\
				fi															;\
			fi																;\
		done																;\
	}
endef

CE_DEPLOYMENT_LIST=eda-api eda-appstore eda-asvr eda-bsvr eda-metrics-server eda-fe eda-keycloak eda-postgres eda-sa eda-sc eda-toolbox
ifeq ($(IS_EDA_CORE_VERSION_24X),0)
CE_DEPLOYMENT_LIST+=eda-cert-checker
endif

.PHONY: eda-is-core-deployment-ready
eda-is-core-deployment-ready: | $(BASE) $(KUBECTL) ## Wait for all of the core pods to launch and be ready
	@$(call WAIT_FOR_DEP,eda-ce)
	@{ \
		CE_CHILDREN_DEPLOYMENTS_LIST="$(CE_DEPLOYMENT_LIST)"; \
		if [[ "$$($(KUBECTL) --namespace $(EDA_CORE_NAMESPACE) get engineconfig engine-config -o jsonpath='{.spec.simulate}')" == "true" ]]; then \
			CE_CHILDREN_DEPLOYMENTS_LIST="$$CE_CHILDREN_DEPLOYMENTS_LIST eda-cx"; \
		fi; \
		echo "$$CE_CHILDREN_DEPLOYMENTS_LIST" | tr ' ' '\n' | \
			$(XARGS_CMD) -P 11 -I {} bash -c '$(call WAIT_FOR_DEP,{})'; \
	}

.PHONY: eda-is-core-ready
eda-is-core-ready: | eda-is-core-deployment-ready is-ce-first-commit-done apps-is-appflow-ready ## Flight checks if core is ready


.PHONY: eda-uninstall-core
eda-uninstall-core: | $(BASE) $(KPT) ; $(info --> KPT: Removing EDA core services) ## Destroy the core kpt deployment
	@{	\
		pushd $(KPT_CORE)				;\
		$(KPT) live destroy				;\
		echo "--> KPT: Core resources reconciled";\
		popd							;\
	}

# Apps that need to be installed in a specific order
# The order of this list how they get installed
APPS_INSTALL_LIST_BUILTIN=
APPS_INSTALL_LIST_BUILTIN += aaa
ifneq ($(IS_EDA_APPS_VERSION_24X),1)
APPS_INSTALL_LIST_BUILTIN += aifabrics
endif
APPS_INSTALL_LIST_BUILTIN += bootstrap
APPS_INSTALL_LIST_BUILTIN += components
APPS_INSTALL_LIST_BUILTIN += config
APPS_INSTALL_LIST_BUILTIN += environment
APPS_INSTALL_LIST_BUILTIN += interfaces
APPS_INSTALL_LIST_BUILTIN += protocols
APPS_INSTALL_LIST_BUILTIN += filters
APPS_INSTALL_LIST_BUILTIN += operatingsystem
APPS_INSTALL_LIST_BUILTIN += qos
APPS_INSTALL_LIST_BUILTIN += routing
APPS_INSTALL_LIST_BUILTIN += routingpolicies
APPS_INSTALL_LIST_BUILTIN += services
APPS_INSTALL_LIST_BUILTIN += siteinfo
APPS_INSTALL_LIST_BUILTIN += system
APPS_INSTALL_LIST_BUILTIN += timing
APPS_INSTALL_LIST_BUILTIN += fabrics
APPS_INSTALL_LIST_BUILTIN += oam
APPS_INSTALL_LIST_BUILTIN += security
APPS_INSTALL_LIST_BUILTIN += topologies

NUMBER_OF_PARALLEL_APP_INSTALLS ?= 20

POD_LABEL_ET=eda.nokia.com/app=eda-toolbox
EDACTL_BIN := /eda/tools/edactl

# macos stock bash does not support associative arrays
# Do not __improve__ with using declare -A
# Syntax for this is "crd|cr" names
# The quotes are important
# To wait on multiple resources in the same gvk, duplicate the line as is
APPFLOW_RESOURCES_TYPES=
APPFLOW_RESOURCES_TYPES += "catalogs.appstore.eda.nokia.com|$(APPS_CATALOG_NAME)"
APPFLOW_RESOURCES_TYPES += "registries.appstore.eda.nokia.com|$(APPS_REGISTRY_NAME)"

.PHONY: apps-is-appflow-ready
apps-is-appflow-ready:
	@{	\
		export ET_POD=$$($(KUBECTL) --namespace $(EDA_CORE_NAMESPACE) get pods -l $(POD_LABEL_ET) --no-headers -o=jsonpath='{.items[*].metadata.name}') ;\
		$(KUBECTL) --namespace $(EDA_CORE_NAMESPACE) exec -it $${ET_POD} \
		-- bash -c 'if [[ ! -f $(EDACTL_BIN) ]]; then echo "--> APPS:FLOW: [ERROR] $(EDACTL_BIN) in the toolbox pod does not exist!" && exit 1; else echo "--> APPS:FLOW: Found $(EDACTL_BIN)"; fi' ;\
		for resources in $(APPFLOW_RESOURCES_TYPES)												;\
		do																						 \
			COUNT=0																				;\
			MAX_WAIT=$(APP_INSTALL_TIMEOUT)														;\
			RESOURCE_FOUND=0																	;\
			RESOURCE_TYPE=$$(echo "$${resources}" | cut -f1 -d'|')								;\
			RESOURCE_NAME=$$(echo "$${resources}" | cut -f2 -d'|')								;\
			echo "--> APPS:FLOW: Waiting for $${RESOURCE_TYPE} - $${RESOURCE_NAME} - $$(date)"	;\
			while [ $$COUNT -lt $$MAX_WAIT ]; do												 \
				found=$$($(KUBECTL) --namespace $(EDA_CORE_NAMESPACE) exec -it $${ET_POD}		 \
				-- bash -c "($(EDACTL_BIN) -o json get $${RESOURCE_TYPE} $${RESOURCE_NAME} | grep -q '(NotFound)') && echo 'no' || echo 'yes'" | tr -d '\r' ) ;\
				if [[ "$${found}" == "yes" ]]; then												 \
					echo "--> APPS:FLOW: $${RESOURCE_TYPE} - $${RESOURCE_NAME} is available -- $$(date)";\
					RESOURCE_FOUND=1															;\
					break																		;\
				fi																				;\
				COUNT=$$((COUNT + 1))															;\
				sleep 2 																		;\
			done																				;\
			if [[ $$RESOURCE_FOUND -ne 1 ]]; then												 \
				echo																			;\
				echo "--> APP:FLOW: [ERROR] Could not find resource using $(EDACTL_BIN) $${RESOURCE_TYPE}:$${RESOURCE_NAME} -- $$(date)";\
				echo 																			;\
				exit 1																			;\
			fi																					;\
		done ;\
	}

### Pre 25.4.x way to install apps

## The @ supressor is not here, its in the $(call ...) where the macro is called
define INSTALL_APP
	{	\
		START=$$(date +%s)																	;\
		export APPS_VENDOR=$(1)																;\
		export APP=$(2)																		;\
		$(KUBECTL) --namespace $(EDA_APPS_INSTALL_NAMESPACE) delete -f $(APPS_INSTALL_CRS)/$${APP}-install-cr.yaml --ignore-not-found	;\
		echo -e "--> INSTALL:APP: [\033[1;34m$${APP}\033[0m] Installing"					;\
		$(KUBECTL) --namespace $(EDA_APPS_INSTALL_NAMESPACE) apply -f $(APPS_INSTALL_CRS)/$${APP}-install-cr.yaml 2>&1 | sed "s/^/    /"	;\
		MAX_WAIT=$(APP_INSTALL_TIMEOUT)														;\
		COUNT=0																				;\
		INSTALLED=0																			;\
		while [ $$COUNT -lt $$MAX_WAIT ]; do												 \
			state=$$($(KUBECTL) --namespace $(EDA_APPS_INSTALL_NAMESPACE) get workflows.core.eda.nokia.com $$APP-$${APPS_VENDOR}-install --no-headers -o=jsonpath='{.status.result}');\
			if [[ "$${state}" == "OK" ]]; then										 		 \
				INSTALLED=1																	;\
				break																		;\
			fi																				;\
			COUNT=$$((COUNT + 1))															;\
			sleep 1 																		;\
		done 																				;\
		if [ $$INSTALLED -ne 1 ] ; then														 \
			echo																			;\
			$(KUBECTL) --namespace $(EDA_APPS_INSTALL_NAMESPACE) get transactionresults -o yaml										;\
			$(KUBECTL) --namespace $(EDA_APPS_INSTALL_NAMESPACE) get workflows -o yaml												;\
			echo "--> INSTALL:APP: [\033[0;31m$${APP}\033[0m] Failed to install, did not reach installed state in $${COUNT}s, it is in $${state}" ;\
			$(KUBECTL) --namespace $(EDA_APPS_INSTALL_NAMESPACE) delete -f $(APPS_INSTALL_CRS)/$${APP}-install-cr.yaml --ignore-not-found	;\
			exit 1 																			;\
		else																				 \
			echo -e "--> INSTALL:APP: [\033[0;32m$${APP}\033[0m] Installed in $$(( $$(date +%s) - $$START ))s" ;\
			$(KUBECTL) --namespace $(EDA_APPS_INSTALL_NAMESPACE) delete -f $(APPS_INSTALL_CRS)/$${APP}-install-cr.yaml --ignore-not-found | sed "s/^/    /"	;\
		fi																					;\
	}
endef

### Post 25.x Bulk app installs

define BUILD_BULK_CRS
{	\
	export TEMPLATE=$(1)														;\
	export BULKCR=$(2)															;\
	export NS=$(3)																;\
	export WFNAME=$(4)															;\
	export OP=$(5)																;\
	cp -fv $${TEMPLATE} $${BULKCR} | $(INDENT_OUT)								;\
	$(YQ) -i '.metadata.namespace = env(NS)' $${BULKCR}							;\
	$(YQ) -i '.metadata.name = env(WFNAME)' $${BULKCR}							;\
	$(YQ) -i '.spec.input.operation = env(OP)' $${BULKCR}						;\
	for APP in $(APPS_INSTALL_LIST_BUILTIN); do									 \
		export single_app_cr=$(APPS_INSTALL_CRS)/$${APP}-$${OP}-cr.yaml			;\
		if [ ! -f $${single_app_cr} ]; then echo "[ERROR] APP install cr does not exist - $${single_app_cr}"  && exit 1; fi;\
		$(YQ) -i '.spec.input.apps += (load(env(single_app_cr)).spec.input.apps[0])' $${BULKCR}	;\
		echo "--> INSTALL:APP:BULK: Adding $${APP} to bulk $${OP} workflow cr"	;\
	done																		;\
	echo "--> INSTALL:APP:BULK: Done $${BULKCR}"								;\
}
endef

## $1 is the name of the workflow cr i.e .metadata.name
## $2 is the workflow cr itself, i.e the yaml file to k apply
## The @ supressor is not here, its in the $(call ...) where the macro is called
define RUN_APP_WF
	{	\
		START=$$(date +%s)																			;\
		export WF_NAME=$(1)																			;\
		export WF_CR=$(2)																			;\
		export OP=$(3)																				;\
		export INFO_HEADER="--> APP:$${OP}: [\033[1;34m$${WF_NAME}\033[0m]"							;\
		export FAIL_HEADER="--> APP:$${OP}: [\033[0;31m$${WF_NAME}\033[0m]"							;\
		export PASS_HEADER="--> APP:$${OP}: [\033[0;32m$${WF_NAME}\033[0m]"							;\
		$(KUBECTL) --namespace $(EDA_APPS_INSTALL_NAMESPACE) delete -f $${WF_CR} --ignore-not-found	;\
		echo -e "$${INFO_HEADER} Executing APP:$${OP}"												;\
		$(KUBECTL) --namespace $(EDA_APPS_INSTALL_NAMESPACE) apply -f $${WF_CR} 2>&1 | $(INDENT_OUT);\
		MAX_WAIT=$(APP_INSTALL_TIMEOUT)																;\
		COUNT=0																						;\
		COMPLETED=0																					;\
		while [ $$COUNT -lt $$MAX_WAIT ]; do														 \
			state=$$($(KUBECTL) --namespace $(EDA_APPS_INSTALL_NAMESPACE) get workflows.core.eda.nokia.com $${WF_NAME} --no-headers -o=jsonpath='{.status.result}');\
			if [[ "$${state}" == "OK" ]]; then														 \
				COMPLETED=1																			;\
				break																				;\
			fi																						;\
			COUNT=$$((COUNT + 1))																	;\
			sleep 1 																				;\
		done 																						;\
		if [ $$COMPLETED -ne 1 ] ; then																 \
			echo																					;\
			$(KUBECTL) --namespace $(EDA_APPS_INSTALL_NAMESPACE) get transactionresults -o yaml		;\
			$(KUBECTL) --namespace $(EDA_APPS_INSTALL_NAMESPACE) get workflows -o yaml				;\
			echo "$${FAIL_HEADER} Failed to $${OP}, did not reach OK state in $${COUNT}s, it is in $${state}";\
			exit 1 																					;\
		else																						 \
			echo -e "$${PASS_HEADER} Done: $${OP} in $$(( $$(date +%s) - $$START ))s"				;\
			$(KUBECTL) --namespace $(EDA_APPS_INSTALL_NAMESPACE) delete -f $${WF_CR} --ignore-not-found 2>&1 | $(INDENT_OUT);\
		fi																							;\
	}
endef

.PHONY: eda-install-apps
eda-install-apps: | $(BASE) $(CATALOG) $(KUBECTL) $(YQ) apps-is-appflow-ready ## Install EDA apps from the appstore catalog
	@echo "--> INFO: EDA_APPS_VERSION=$(EDA_APPS_VERSION)"
ifeq ($(USE_BULK_APP_INSTALL),1)
	@$(call BUILD_BULK_CRS,$(APP_INSTALL_BULK_TEMPLATE),$(APP_INSTALL_BULK_CR),$(EDA_APPS_INSTALL_NAMESPACE),$(APP_INSTALL_BULK_WF_NAME),install)
	@{	\
		apps=($(APPS_INSTALL_LIST_BUILTIN))																;\
		echo "--> INSTALL:APP:BULK: Installing $${#apps[@]} apps in bulk mode from catalog $(CATALOG)"	;\
	}
	@$(call RUN_APP_WF,$(APP_INSTALL_BULK_WF_NAME),$(APP_INSTALL_BULK_CR),install)
else
	@echo "--> INSTALL:APP: Installing apps from catalog $(CATALOG)"
	@echo $(APPS_INSTALL_LIST_BUILTIN) | tr ' ' '\n' | \
		$(XARGS_CMD)  -P $(words $(APPS_INSTALL_LIST_BUILTIN)) -I {} bash -c '$(call INSTALL_APP,$(APPS_VENDOR),{})'
endif

.PHONY: eda-configure-playground
eda-configure-playground: | instantiate-kpt-setters-work-file ## Configure the playground packages
	@{	\
		pushd $(KPT_PLAYGROUND) &> /dev/null || (echo "[ERROR] Could not change cwd to $(KPT_PLAYGROUND) from $$(pwd)" && exit 1)	;\
		echo "--> KPT:PG: Configuring the playground package"		;\
		$(KPT) fn eval --image $(APPLY_SETTER_IMG) \
		--truncate-output=false \
		--fn-config $(KPT_SETTERS_WORK_FILE) 2>&1 | sed 's/^/    /' ;\
		popd &> /dev/null || (echo "[ERROR] Could not change cwd to $(KPT_PLAYGROUND) from $$(pwd)" && exit 1)						;\
	}

.PHONY: eda-bootstrap
eda-bootstrap: | $(BASE) $(KPT) eda-configure-playground; $(info --> KPT: Bootstrapping EDA) @ ## Load allocation pools, secrets, node profiles...
	@$(call INSTALL_KPT_PACKAGE,$(KPT_PLAYGROUND),EDA PLAYGROUND)

##@ Northbound extensions

API_CFG_LB_SVC ?= $(CFG)/eda-api-svc.yaml

.PHONY: eda-create-api-lb-svc
eda-create-api-lb-svc: | $(BASE) $(KPT) ; $(info --> Creating a new API LoadBalancer Service) @ ## Create an additional API load-balancer service, req: API_LB_POOL_NAME=<lb pool name from where to allocate ip> opt: API_LB_SVC_NAME=<different name>
	@{	\
		setter_args=""																							;\
		if [[ -z "$(API_LB_POOL_NAME)" ]]; then																	 \
			echo "[ERROR] - API_LB_POOL_NAME, the name of the loadbalancer pool should be specified" && exit 1	;\
		else																									 \
			setter_args="API_LB_POOL_NAME=$(API_LB_POOL_NAME)"													;\
		fi																										;\
		if [[ ! -z "$(API_LB_SVC_NAME)" ]]; then																 \
			setter_args="$${setter_args} API_LB_SVC_NAME=$(API_LB_SVC_NAME)"									;\
		fi																										;\
		setter_args="$$setter_args EDA_CORE_NAMESPACE=$(EDA_CORE_NAMESPACE)"									;\
		cat $(API_CFG_LB_SVC) | $(KPT) fn eval - --image $(APPLY_SETTER_IMG) --truncate-output=false --output unwrap -- $${setter_args} | $(KUBECTL) apply -f - | sed 's/^/    /';\
	}

##@ Topology

.PHONY: template-topology
template-topology:  ## Create topology config-map from the topology input
	$(YQ) eval-all '{"apiVersion": "v1","kind": "ConfigMap","metadata": {"name": "$(TOPO_CONFIGMAP_NAME)"},"data": {"eda.json": (. | tojson)}} ' $(TOPO)


.PHONY: topology-load
topology-load:  ## Load a topology file TOPO=<file>
	@{	\
		echo "--> TOPO: JSON Processing"					;\
		if [[ $(IS_EDA_CORE_VERSION_24X) -eq 1 ]]; then		 \
			$(YQ) eval-all '{"apiVersion": "v1","kind": "ConfigMap","metadata": {"name": "$(TOPO_CONFIGMAP_NAME)"},"data": {"eda.json": (. | tojson)}} ' $(TOPO) | $(KUBECTL)  --namespace $(EDA_USER_NAMESPACE) apply -f -	;\
		else												 \
			$(YQ) eval-all '{"apiVersion": "v1","kind": "ConfigMap","metadata": {"name": "$(TOPO_CONFIGMAP_NAME)"},"data": {"eda.yaml": load_str("$(TOPO)")}}' $(TOPO) | $(KUBECTL)  --namespace $(EDA_USER_NAMESPACE) apply -f -	;\
		fi													;\
		if [[ $(IS_EDA_CORE_VERSION_24X) -eq 0 ]]; then	$(KUBECTL) --namespace $(EDA_USER_NAMESPACE) apply -f $(SIMTOPO); fi ;\
		echo "--> TOPO: config created in cluster"			;\
		export POD_NAME=$$($(KUBECTL) --namespace $(EDA_CORE_NAMESPACE) get pod -l eda.nokia.com/app=apiserver -o jsonpath="{.items[0].metadata.name}"); \
		echo "--> TOPO: Using POD_NAME: $$POD_NAME"			;\
		echo "--> TOPO: Checking if $$POD_NAME is Running"	;\
		while [ "$$($(KUBECTL) --namespace $(EDA_CORE_NAMESPACE) get pod $$POD_NAME -o jsonpath='{.status.phase}')" != "Running" ]; do \
			echo "--> TOPO: Waiting for $$POD_NAME to be in Running state...";\
			sleep 5											;\
		done												;\
		$(KUBECTL) --namespace $(EDA_CORE_NAMESPACE) exec -it $$POD_NAME -- bash -c "/app/api-server-topo -n $(EDA_USER_NAMESPACE)" | sed 's/^/    /';\
	}

##@ Utility Functions

PORT_FORWARD_TO_API_SVC ?= eda-api

.PHONY: enable-ui-port-forward-service
enable-ui-port-forward-service: | $(KUBECTL) ## Enable and start the UI port forward systemd service
	@{ \
		MAKE_PATH=$$(which make); \
		SVC_NAME="eda-ui.service"; \
		CUR_USER=$$(id -un); \
		sed "s|__make|$${MAKE_PATH}|g; s|__pg_path|$(TOP_DIR)|g; s|__user|$${CUR_USER}|g" $(CFG)/$${SVC_NAME} | sudo tee /etc/systemd/system/$${SVC_NAME} > /dev/null; \
		sudo systemctl daemon-reload; \
		sudo systemctl enable $${SVC_NAME}; \
		sudo systemctl start $${SVC_NAME}; \
		CLUSTER_EXT_DOMAIN_NAME=$$($(KUBECTL) --namespace $(EDA_CORE_NAMESPACE) get engineconfigs.core.eda.nokia.com engine-config -ojsonpath='{.spec.cluster.external.domainName}')	;\
		CLUSTER_EXT_HTTPS_PORT=$$($(KUBECTL) --namespace $(EDA_CORE_NAMESPACE) get engineconfigs.core.eda.nokia.com engine-config -ojsonpath='{.spec.cluster.external.httpsPort}')	;\
		echo "--> The UI can be accessed using https://$${CLUSTER_EXT_DOMAIN_NAME}:$${CLUSTER_EXT_HTTPS_PORT}"; \
	}

.PHONY: start-ui-port-forward
start-ui-port-forward: | $(BUILD) $(KUBECTL) stop-ui-port-forward ## Start a port from the eda api service to the host at port specified by EXT_HTTPS_PORT
	@{	\
		echo "--> Exposing the UI to the host"																																									;\
		CLUSTER_EXT_DOMAIN_NAME=$$($(KUBECTL) --namespace $(EDA_CORE_NAMESPACE) get engineconfigs.core.eda.nokia.com engine-config -ojsonpath='{.spec.cluster.external.domainName}')							;\
		CLUSTER_EXT_HTTPS_PORT=$$($(KUBECTL) --namespace $(EDA_CORE_NAMESPACE) get engineconfigs.core.eda.nokia.com engine-config -ojsonpath='{.spec.cluster.external.httpsPort}')								;\
		STDERR_LOG="$(BUILD)/eda-port-forward-$$(date +"%F-%H-%M-%S-%N").log"																																	;\
		port_forward_cmd="nohup $(KUBECTL) --namespace $(EDA_CORE_NAMESPACE) port-forward service/$(PORT_FORWARD_TO_API_SVC) --address 0.0.0.0 $${CLUSTER_EXT_HTTPS_PORT}:443 > /dev/null 2> $${STDERR_LOG} &"	;\
		if [[ $${CLUSTER_EXT_HTTPS_PORT} -eq 443 ]]; then port_forward_cmd="sudo -E $${port_forward_cmd}" ; fi 																									;\
		eval $$port_forward_cmd 																																												;\
		PORT_FWD_PID=$$!																																														;\
		sleep 10s																																																;\
		if ! kill -0 $${PORT_FWD_PID} > /dev/null 2>&1 ; then																																					 \
			echo ""																																																;\
			echo "[ERROR] Could not start port forward process $${PORT_FWD_PID} died"																															;\
			cat $${STDERR_LOG} | $(INDENT_OUT_ERROR)																																							;\
			echo "        Perhaps something is already bound on 0.0.0.0:$${CLUSTER_EXT_HTTPS_PORT} ?"																											;\
			echo "        Port binds can be checked using one of the below commands:"																															;\
			echo "          ss -ltupnHO src 0.0.0.0:$${CLUSTER_EXT_HTTPS_PORT}"																																	;\
			echo "          netstat -ltupn src | grep 0.0.0.0:$${CLUSTER_EXT_HTTPS_PORT}"																														;\
			exit 1																																																;\
		fi																																																		;\
		echo "--> Started background port forward with process id: $${PORT_FWD_PID}"																															;\
		echo "--> The UI can be accessed using https://$${CLUSTER_EXT_DOMAIN_NAME}:$${CLUSTER_EXT_HTTPS_PORT}"																									;\
	}

.PHONY: stop-ui-port-forward
stop-ui-port-forward: | $(KUBECTL) ## Stop a port forward launched by this playground only
	@{	\
		PROCESS=$$(ps -ef | grep '$(KUBECTL) --namespace $(EDA_CORE_NAMESPACE) port-forward service/$(PORT_FORWARD_TO_API_SVC) --address 0.0.0.0' | grep -v grep || true)	;\
		if [[ "$${PROCESS}" == "" ]]; then echo "--> INFO: no port forward found - nothing to stop" && exit 0 ; fi															;\
		PID_OF_KUBECTL_FWD=$$(echo "$${PROCESS}" | awk '{ print $$2 }')																										;\
		if [[ "$${PID_OF_KUBECTL_FWD}" == "1" ]]; then echo "--> INFO: Found port-forward at pid $${PID_OF_KUBECTL_FWD} - refusing to kill init pid!" && exit 1 ; fi		;\
		kill -9 $${PID_OF_KUBECTL_FWD}																																		;\
		echo "--> INFO: Stopped port forward running in process id $${PID_OF_KUBECTL_FWD}"																					;\
		echo "          $${PROCESS}"																																		;\
	}


.PHONY: open-toolbox
open-toolbox: ## Log into the toolbox pod
	$(KUBECTL) --namespace $(EDA_CORE_NAMESPACE) exec -it $$($(KUBECTL) --namespace $(EDA_CORE_NAMESPACE) get pods -l eda.nokia.com/app=eda-toolbox -o=jsonpath='{.items[*].metadata.name}') -- env "TERM=xterm-256color" bash -l

.PHONY: e9s
e9s: ## Run e9s application
	$(KUBECTL) --namespace $(EDA_CORE_NAMESPACE) exec -it $$($(KUBECTL) --namespace $(EDA_CORE_NAMESPACE) get pods -l eda.nokia.com/app=eda-toolbox -o=jsonpath='{.items[*].metadata.name}') -- env "TERM=xterm-256color" /eda/tools/e9s

##@ Host setup

.PHONY: install-docker
install-docker: ## Install docker-ce engine
	$(CURL) -L https://containerlab.dev/setup | bash -s "install-docker"

.PHONY: configure-sysctl-params
configure-sysctl-params:
	@{	\
		(sudo mkdir -p /etc/sysctl.d) 															&& \
		(sudo cp -v $(TOP_DIR)/configs/90-eda.conf /etc/sysctl.d/90-eda.conf | sed 's/^/    /') && \
		(sudo sysctl --system | sed 's/^/    /')												&& \
		echo "--> INFO: Reload daemon and restart docker service"								&& \
		(sudo systemctl daemon-reload)															&& \
		(sudo systemctl restart docker) ;\
	}

define is-command-present
{	\
	bin=$$(echo "$1" | cut -f1 -d'|')															;\
	remedy=$$(echo "$1" | cut -f2- -d'|')														;\
	if ! command -v "$${bin}" 2>&1 >/dev/null; then												 \
    	echo -e "--> HOST: $(ERROR) $${bin} not found in \$$PATH - $${remedy//_/' '}" && exit 1	;\
	else 																						 \
		echo -e "--> HOST: $(OK) Found host tools $$(command -v $$bin)"							;\
	fi 																							;\
}
endef

define is-there-enough-free-disk-space
{	\
	available_space=$$(df --output=avail $(TOP_DIR) | tail -n1) ;\
	if [[ $${available_space} -lt $(1) ]]; then														 \
		echo -e "--> HOST: $(ERROR) Available disk space is lower than the recommended threshold"	;\
		echo "                  See: https://docs.eda.dev/getting-started/try-eda/"					;\
		df -h $(TOP_DIR) 2>&1 | sed 's/^/                  /'										;\
		exit 1 																						;\
	else 																							 \
		echo -e "--> HOST: $(OK) Available disk requirments meet"									;\
	fi 																								;\
}
endef

define is-user-in-group
{	\
	user=$$(whoami)																		;\
	group=$(1)																			;\
	if id -nG "$${user}" | grep -qw "$${group}"; then 									 \
		echo -e "--> HOST: $(OK) User:$${user} is part of the group:$${group}"			;\
	else 																				 \
		echo -e "--> HOST: $(ERROR) User:$${user} is not part of the group:$${group}"	;\
		echo    "                    Please add $${user} to the $${group}"				;\
		echo    "                    sudo usermod -aG $${group} $${user}"				;\
		exit 1 																			;\
	fi 																					;\
}
endef

define check-sysctl-value
{	\
	value=$$(sysctl -n $(1)) 																		;\
	if [[ $$value -lt $2 ]]; then 																	 \
		echo -e "--> HOST: $(ERROR) sysctl param $1=$$value is lower than the recommended value $2"	;\
		echo "                    Please run make configure-sysctl-params" 							;\
		exit 1 																						;\
	else 																							 \
		echo -e "--> HOST: $(OK) sysctl $1=$2" 														;\
	fi 																								;\
}
endef
# Use _ to denote space since make just splits it in a list :bleh
# binary_name|error_message_when_not_found
LIST_OF_HOST_TOOLS=
LIST_OF_HOST_TOOLS += git|Please_install_git_using_the_system_package_manager
LIST_OF_HOST_TOOLS += docker|Please_run:_make_install-docker

.PHONY: verify-host-config
verify-host-config: ## Verify host has the required params for a kind based setup
	@$(foreach tool,$(LIST_OF_HOST_TOOLS),$(call is-command-present,$(tool));)
	@$(call is-user-in-group,docker)
	@$(call is-there-enough-free-disk-space,$(MIN_DISK_SPACE))
	@$(call check-sysctl-value,fs.inotify.max_user_watches,$(FS_NOTIFY_MAX_USER_WATCHES))
	@$(call check-sysctl-value,fs.inotify.max_user_instances,$(FD_NOTIFY_MAX_USER_INSTANCES))

##@ NODE CLI access
define NODE_CLI
	$(KUBECTL) --namespace $(EDA_CORE_NAMESPACE) exec -it $$($(KUBECTL) --namespace $(EDA_CORE_NAMESPACE) get pods -l cx-pod-name=$(1) -o=jsonpath='{.items[*].metadata.name}') -- bash -c 'sudo sr_cli' -l
endef

.PHONY: node-ssh
node-ssh: ## Connect to a node, specify name using NODE=leaf1-1
	@{  \
		if [[ -z "$(NODE)" ]]; then \
			echo "[ERROR] Please specify the name of the node using NOODE=<name>";\
			echo "        Available nodes are:" ;\
			echo "$$($(KUBECTL) get pods -l cx-cluster-name=eda -o=jsonpath='{.items[*].metadata.labels.cx-pod-name}')" | sed 's/^/        /';\
			exit 1;\
		fi;\
	}
	$(call NODE_CLI,$(NODE))

.PHONY: leaf1-ssh
leaf1-ssh: ## Connect to leaf1
	$(call NODE_CLI,leaf1-1)

.PHONY: leaf2-ssh
leaf2-ssh: ## Connect to leaf2
	$(call NODE_CLI,leaf2-1)

.PHONY: spine1-ssh
spine1-ssh: ## Connect to spine1
	$(call NODE_CLI,spine1-1)

##@ Cleanup

.PHONY: teardown-topology
teardown-topology: ## Remove all simulated toplogy nodes
	$(MAKE) -C $(TOP_DIR) topology-load TOPO=$(TOPO_EMPTY)

.PHONY: teardown-cluster
teardown-cluster: $(KIND) ## Teardown the kind cluster
	@$(KIND) delete clusters $(KIND_CLUSTER_NAME)

.PHONY: clean
clean: teardown-cluster ## Remove the cluster, downloaded packages and tools
	@rm -rf $(BUILD) $(TOOLS) $(KPT_PKG) $(CATALOG)

##@ Logs

POD_LABEL_FD=eda.nokia.com/app=fluentd

.PHONY: logs
logs: ## Show me cluster wide logs
	$(KUBECTL) --namespace $(EDA_CORE_NAMESPACE) exec -it $$($(KUBECTL) --namespace $(EDA_CORE_NAMESPACE) get pods -l $(POD_LABEL_FD) --no-headers -o=jsonpath='{.items[*].metadata.name}') -- bash -c "lnav /var/log/eda/*"

.PHONY: logs-collect
logs-collect: | $(KUBECTL) ## Get the logs from the cluster LOGS_DEST=<custom location>
	@{	\
		export TO=$(LOGS_DEST)	;\
		mkdir -p $${TO}			;\
		set +e ;\
		echo "--> This is collected from $(TOP_DIR)" >> $${TO}/top-dir ;\
		echo "--> Cluster name is $(KIND_CLUSTER_NAME)" >> $${TO}/cluster-name ;\
		$(KUBECTL) --namespace $(EDA_CORE_NAMESPACE) cp $$($(KUBECTL) --namespace $(EDA_CORE_NAMESPACE) get pods -l $(POD_LABEL_FD) --no-headers -o=jsonpath='{.items[*].metadata.name}'):/var/log/eda "$${TO}"/	;\
		docker ps -a >> $${TO}/running-containers ;\
		$(KIND) export logs $${TO} --name $(KIND_CLUSTER_NAME) ;\
		echo "--> Logs are stored in $${TO}" ;\
	}

##@ View config options

LIST_SETTER_CMD := $(KPT) fn eval --image gcr.io/kpt-fn/list-setters:v0.1.0 --truncate-output=false 2>&1 | grep -v -e '^\[RUNNING\].*$$' -e'^\[PASS\].*$$' -e'\ *Results\:.*$$' | awk '{$$1=$$1;print}'

define show-kpt-setter-in-dir
	{	\
		pushd $1 &> /dev/null	;\
		$(LIST_SETTER_CMD)		;\
		popd &> /dev/null		;\
	}
endef

.PHONY: list-kpt-setters-core
list-kpt-setters-core: | $(KPT) ## Show the available kpt setter for the eda-core package
	@$(call show-kpt-setter-in-dir,$(KPT_CORE))

.PHONY: list-kpt-setters-external-packages
list-kpt-setters-external-packages: | $(KPT) ## Show the available kpt setter for the external-packages
	@$(call show-kpt-setter-in-dir,$(KPT_EXT_PKGS))

.PHONY: list-kpt-setters-playground
list-kpt-setters-playground: | $(KPT) ## Show the available kpt setter for the eda-playground package
	@$(call show-kpt-setter-in-dir,$(KPT_PLAYGROUND))

.PHONY: kpt-set-ext-arm-images
kpt-set-ext-arm-images: | $(KPT) $(BUILD) $(CFG) ## Set ARM versions of the images
	@{	\
		$(YQ) eval ".data.CMCA_IMG = \"quay.io/jetstack/cert-manager-cainjector:v1.16.2\"" -i $(KPT_SETTERS_WORK_FILE); \
		$(YQ) eval ".data.TRUSTMGRBUNDLE_IMG = \"quay.io/jetstack/cert-manager-package-debian:20210119.0\"" -i $(KPT_SETTERS_WORK_FILE); \
		$(YQ) eval ".data.TRUSTMGR_IMG = \"quay.io/jetstack/trust-manager:v0.15.0\"" -i $(KPT_SETTERS_WORK_FILE); \
		$(YQ) eval ".data.CMCT_IMG = \"quay.io/jetstack/cert-manager-controller:v1.16.2\"" -i $(KPT_SETTERS_WORK_FILE); \
		$(YQ) eval ".data.CMWH_IMG = \"quay.io/jetstack/cert-manager-webhook:v1.16.2\"" -i $(KPT_SETTERS_WORK_FILE); \
		$(YQ) eval ".data.CSI_DRIVER_IMG = \"quay.io/jetstack/cert-manager-csi-driver:v0.10.1\"" -i $(KPT_SETTERS_WORK_FILE); \
		$(YQ) eval ".data.FB_IMG = \"cr.fluentbit.io/fluent/fluent-bit:3.0.7\"" -i $(KPT_SETTERS_WORK_FILE); \
		$(YQ) eval ".data.GOGS_IMG_TAG = \"ghcr.io/gogs/gogs:0.13.0\"" -i $(KPT_SETTERS_WORK_FILE); \
		$(YQ) eval ".data.CSI_REGISTRAR_IMG = \"k8s.gcr.io/sig-storage/csi-node-driver-registrar:v2.12.0\"" -i $(KPT_SETTERS_WORK_FILE); \
		$(YQ) eval ".data.CSI_LIVPROBE_IMG = \"registry.k8s.io/sig-storage/livenessprobe:v2.12.0\"" -i $(KPT_SETTERS_WORK_FILE); \
	}

.PHONY: try-eda
try-eda: | download-tools download-pkgs update-pkgs $(if $(NO_KIND),,kind) $(if $(NO_LB),,metallb) install-external-packages eda-configure-core eda-install-core eda-is-core-ready eda-install-apps eda-bootstrap $(if $(filter true,$(SIMULATE)),topology-load,) start-ui-port-forward
	@echo "--> INFO: EDA is launched"
#	@echo "--> INFO: The UI port forward can be started using 'make start-ui-port-forward'"


##@ Help me

.PHONY: help
help:  ## Show the help menu
	@sed -ne 's/^\([^[:space:]]*\):.*##/\1\t|\t/p' $(MAKEFILE_LIST) | sort | column -t -s $$'\t' | pager

.PHONY: ls-versions-core
ls-versions-core: | $(KPT_PKG) ## List the core versions available in the kpt package
	@echo "--> INFO: Available core versions are:"
	@git -C $(KPT_PKG) tag | sort --version-sort --reverse | $(INDENT_OUT)
	@echo "--> INFO: Selected core version is $(EDA_CORE_VERSION)"

.PHONY: ls-versions-apps
ls-versions-apps: | $(CATALOG) ## List the app sets available in the catalog
	@echo "--> INFO: Available app sets are:"
	@git -C $(CATALOG) tag --list 'v[0-9]*' | sort --version-sort --reverse | $(INDENT_OUT)
	@echo "--> INFO: Selected app set is $(EDA_APPS_VERSION)"


define __mkfile1337_internal_state
column -s '|' -t <<'EOF'
TOP_DIR | $(TOP_DIR)
TIMEOUT_NODE_READY | $(TIMEOUT_NODE_READY)
KIND_CLUSTER_NAME | $(KIND_CLUSTER_NAME)
CE_DEPLOYMENT_LIST | $(CE_DEPLOYMENT_LIST)
EDA_CORE_VERSION | $(EDA_CORE_VERSION)
EDA_APPS_VERSION | $(EDA_APPS_VERSION)
EOF
endef

export mkfile1337_internal_state = $(call __mkfile1337_internal_state)

# _ hides the target from shell auto completion
.PHONY: _ls-playground-state
_ls-playground-state:; @ eval "$$mkfile1337_internal_state"