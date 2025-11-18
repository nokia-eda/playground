# To enable these overrides, the user must define USE_ASSET_HOST=1 in prefs.mk
ifeq ($(USE_ASSET_HOST),1)

## Sanity checks
## ----------------------------------------------------------------------------|
ifndef ASSET_HOST
$(error [ERROR] --> ASSET_HOST must be defined in prefs.mk for USE_ASSET_HOST=$(USE_ASSET_HOST) mode of operation)
endif

ifndef ASSET_HOST_GIT_USERNAME
$(error [ERROR] --> ASSET_HOST_GIT_USERNAME must be defined in prefs.mk for USE_ASSET_HOST=$(USE_ASSET_HOST) mode of operation)
endif

ifndef ASSET_HOST_GIT_PASSWORD
$(error [ERROR] --> ASSET_HOST_GIT_PASSWORD must be defined in prefs.mk for USE_ASSET_HOST=$(USE_ASSET_HOST) mode of operation)
endif

ifndef ASSET_HOST_ARTIFACTS_USERNAME
$(error [ERROR] --> ASSET_HOST_ARTIFACTS_USERNAME must be defined in prefs.mk for USE_ASSET_HOST=$(USE_ASSET_HOST) mode of operation)
endif

ifndef ASSET_HOST_ARTIFACTS_PASSWORD
$(error [ERROR] --> ASSET_HOST_ARTIFACTS_PASSWORD must be defined in prefs.mk for USE_ASSET_HOST=$(USE_ASSET_HOST) mode of operation)
endif
## Sanity checks end

## Asset hosts configuration overrides
## ----------------------------------------------------------------------------|

ASSET_HOST_REGISTRY_URL := $(ASSET_HOST)
ASSET_HOST_GIT_URL := http://$(ASSET_HOST_GIT_USERNAME):$(ASSET_HOST_GIT_PASSWORD)@$(ASSET_HOST)/git/eda
ASSET_HOST_ARTIFACTS_URL := http://$(ASSET_HOST_ARTIFACTS_USERNAME):$(ASSET_HOST_ARTIFACTS_PASSWORD)@$(ASSET_HOST)/artifacts

# Allow the user to override these from prefs.mk
KPT_PKG_BRANCH ?= main
CATALOG_PKG_BRANCH ?= main
CONNECT_PKG_BRANCH ?= main

EDA_KPT_PKG_SRC ?= $(ASSET_HOST_GIT_URL)/kpt.git --branch $(KPT_PKG_BRANCH)
CATALOG_PKG_SRC ?= $(ASSET_HOST_GIT_URL)/catalog.git --branch $(CATALOG_PKG_BRANCH)
K8S_HELM_PKG_SRC ?= $(ASSET_HOST_GIT_URL)/connect-k8s-helm-charts.git --branch $(CONNECT_PKG_BRANCH)

## Tool Versions:
KUBECTL_VERSION ?= v1.34.1
HELM_VERSION ?= v3.17.0
KPT_VERSION ?= v1.0.0-beta.57
K9S_VERSION ?= v0.50.16
YQ_VERSION ?= v4.42.1

KUBECTL_SRC := $(ASSET_HOST_ARTIFACTS_URL)/kubectl-$(KUBECTL_VERSION)
HELM_SRC := $(ASSET_HOST_ARTIFACTS_URL)/helm-$(HELM_VERSION).tar.gz
KPT_SRC := $(ASSET_HOST_ARTIFACTS_URL)/kpt-$(KPT_VERSION)
K9S_SRC := $(ASSET_HOST_ARTIFACTS_URL)/k9s-$(K9S_VERSION).tar.gz
YQ_SRC := $(ASSET_HOST_ARTIFACTS_URL)/yq-$(YQ_VERSION)

# APPLY_SETTER_IMG ?= $(ASSET_HOST_REGISTRY_URL)/srl-labs/kpt-apply-setters:0.1.1

## Self-host KPT overrides
## ----------------------------------------------------------------------------|
APP_REGISTRY_SKIPTLSVERIFY ?= true
APP_REGISTRY_MIRROR ?= $(ASSET_HOST_REGISTRY_URL)
APP_CATALOG ?= http://$(ASSET_HOST)/git/eda/catalog.git
GH_CATALOG_TOKEN ?= $(shell echo -n "$(ASSET_HOST_GIT_PASSWORD)" | base64)
GH_CATALOG_USER ?= $(shell echo -n "$(ASSET_HOST_GIT_USERNAME)" | base64)
YANG_REMOTE_URL ?= http://$(ASSET_HOST)/artifacts
LLM_DB_REMOTE_URL ?= http://$(ASSET_HOST)/artifacts
endif
# Close ifeq ($(USE_ASSET_HOST),1)
