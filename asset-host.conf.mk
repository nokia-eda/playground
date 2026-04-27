# To enable these overrides, the user must define USE_ASSET_HOST=1 in prefs.mk
ifeq ($(USE_ASSET_HOST),1)

# Get make to print some newlines in $info/$error - note the double blank lines
define n


endef

## Sanity checks
## ----------------------------------------------------------------------------|
ifdef ASSET_HOST
# Are we using the unified host ?
$(info --> ASSET_HOST=$(ASSET_HOST))
else
# Are we in endpoint mode ?
ifneq ($(and $(ASSET_HOST_REGISTRY),$(ASSET_HOST_GIT),$(ASSET_HOST_ARTIFACTS)),)
$(info --> SPLIT ASSET_HOST mode)
else
$(error $n\
[ERROR] Incomplete configuration!$n\
USE_ASSET_HOST=$(USE_ASSET_HOST) mode of operation enabled!$n\
Either ASSET_HOST=$(ASSET_HOST)$n\
OR$n\
Set of endpoints: ASSET_HOST_REGISTRY=$(ASSET_HOST_REGISTRY), ASSET_HOST_GIT=$(ASSET_HOST_GIT), ASSET_HOST_ARTIFACTS=$(ASSET_HOST_ARTIFACTS)$n\
must be defined in prefs.mk)
endif
endif

ifndef B64_ASSET_HOST_GIT_USERNAME
$(error [ERROR] --> B64_ASSET_HOST_GIT_USERNAME must be defined in prefs.mk for USE_ASSET_HOST=$(USE_ASSET_HOST) mode of operation)
endif

ifndef B64_ASSET_HOST_GIT_PASSWORD
$(error [ERROR] --> B64_ASSET_HOST_GIT_PASSWORD must be defined in prefs.mk for USE_ASSET_HOST=$(USE_ASSET_HOST) mode of operation)
endif

ifndef B64_ASSET_HOST_ARTIFACTS_USERNAME
$(error [ERROR] --> B64_ASSET_HOST_ARTIFACTS_USERNAME must be defined in prefs.mk for USE_ASSET_HOST=$(USE_ASSET_HOST) mode of operation)
endif

ifndef B64_ASSET_HOST_ARTIFACTS_PASSWORD
$(error [ERROR] --> B64_ASSET_HOST_ARTIFACTS_PASSWORD must be defined in prefs.mk for USE_ASSET_HOST=$(USE_ASSET_HOST) mode of operation)
endif

# Optional for the unified asset host
# ifndef B64_ASSET_HOST_REGISTRY_USERNAME
# $(error [ERROR] --> B64_ASSET_HOST_REGISTRY_USERNAME must be defined in prefs.mk for USE_ASSET_HOST=$(USE_ASSET_HOST) mode of operation)
# endif

# ifndef B64_ASSET_HOST_REGISTRY_PASSWORD
# $(error [ERROR] --> B64_ASSET_HOST_REGISTRY_PASSWORD must be defined in prefs.mk for USE_ASSET_HOST=$(USE_ASSET_HOST) mode of operation)
# endif

## Sanity checks end

## Asset hosts configuration overrides
## ----------------------------------------------------------------------------|

# Decode the auth
ASSET_HOST_GIT_USERNAME ?= $(shell echo -n "$(B64_ASSET_HOST_GIT_USERNAME)" | base64 -d)
ASSET_HOST_GIT_PASSWORD ?= $(shell echo -n "$(B64_ASSET_HOST_GIT_PASSWORD)" | base64 -d)
ASSET_HOST_ARTIFACTS_USERNAME ?= $(shell echo -n "$(B64_ASSET_HOST_ARTIFACTS_USERNAME)" | base64 -d)
ASSET_HOST_ARTIFACTS_PASSWORD ?= $(shell echo -n "$(B64_ASSET_HOST_ARTIFACTS_PASSWORD)" | base64 -d)
ASSET_HOST_REGISTRY_USERNAME ?= $(shell echo -n "$(B64_ASSET_HOST_REGISTRY_USERNAME)" | base64 -d)
ASSET_HOST_REGISTRY_PASSWORD ?= $(shell echo -n "$(B64_ASSET_HOST_REGISTRY_PASSWORD)" | base64 -d)

# Define the endpoints if using the unified eda asset-host, still allow the user to override them if need be
ifdef ASSET_HOST
ASSET_HOST_REGISTRY ?= $(ASSET_HOST)
ASSET_HOST_GIT ?= https://$(ASSET_HOST)/git/$(ASSET_HOST_GIT_USERNAME)
ASSET_HOST_ARTIFACTS ?= http://$(ASSET_HOST)/artifacts
ASSET_HOST_ARTIFACTS_TOOLS_URL ?= https://$(ASSET_HOST)/artifacts
else
# The user provides the complete url endpoint with the scheme
ASSET_HOST_ARTIFACTS_TOOLS_URL ?= $(ASSET_HOST_ARTIFACTS)
endif

ASSET_HOST_REGISTRY_URL := $(ASSET_HOST_REGISTRY)
ASSET_HOST_GIT_URL := $(ASSET_HOST_GIT)
ASSET_HOST_ARTIFACTS_URL := $(ASSET_HOST_ARTIFACTS)

# These set of url's are passed onto k8s/eda resources
ASSET_HOST_APP_CATALOG := $(ASSET_HOST_GIT_URL)/catalog.git

# Allow the user to override these from prefs.mk
KPT_PKG_BRANCH ?= main
CATALOG_PKG_BRANCH ?= main
CONNECT_PKG_BRANCH ?= main

# Ignore self signed certificates
INSECURE ?= 1

ifdef ASSET_HOST_GIT_USERNAME
GIT_AUTH ?= GIT_USERNAME_VAR=$(ASSET_HOST_GIT_USERNAME) GIT_PASSWORD_VAR=$(ASSET_HOST_GIT_PASSWORD)
endif

EDA_KPT_PKG_SRC ?= $(ASSET_HOST_GIT_URL)/kpt.git --branch $(KPT_PKG_BRANCH)
CATALOG_PKG_SRC ?= $(ASSET_HOST_GIT_URL)/catalog.git --branch $(CATALOG_PKG_BRANCH)
K8S_HELM_PKG_SRC ?= $(ASSET_HOST_GIT_URL)/connect-k8s-helm-charts.git --branch $(CONNECT_PKG_BRANCH)

## Tool Versions:
KUBECTL_VERSION ?= v1.34.1
HELM_VERSION ?= v3.17.0
KPT_VERSION ?= v1.0.0-beta.57
K9S_VERSION ?= v0.50.16
YQ_VERSION ?= v4.42.1

CURL_AUTH ?= -u $(ASSET_HOST_ARTIFACTS_USERNAME):$(ASSET_HOST_ARTIFACTS_PASSWORD)

KUBECTL_SRC := $(ASSET_HOST_ARTIFACTS_TOOLS_URL)/kubectl-$(KUBECTL_VERSION)
HELM_SRC := $(ASSET_HOST_ARTIFACTS_TOOLS_URL)/helm-$(HELM_VERSION).tar.gz
KPT_SRC := $(ASSET_HOST_ARTIFACTS_TOOLS_URL)/kpt-$(KPT_VERSION)
K9S_SRC := $(ASSET_HOST_ARTIFACTS_TOOLS_URL)/k9s-$(K9S_VERSION).tar.gz
YQ_SRC := $(ASSET_HOST_ARTIFACTS_TOOLS_URL)/yq-$(YQ_VERSION)
EDABUILDER_SRC_ROOT := $(ASSET_HOST_ARTIFACTS_TOOLS_URL)
EDACTL_SRC_ROOT := $(ASSET_HOST_ARTIFACTS_TOOLS_URL)

# APPLY_SETTER_IMG ?= $(ASSET_HOST_REGISTRY_URL)/srl-labs/kpt-apply-setters:0.1.1

ASSET_HOST_REGISTRY_USING_AUTH ?= 0
# Figure out the secrets
ifdef B64_ASSET_HOST_REGISTRY_USERNAME
ASSET_HOST_REGISTRY_USING_AUTH := 1
# Values for the registry.nokia.eda.com CR
GH_REGISTRY_USER := $(B64_ASSET_HOST_REGISTRY_USERNAME)
GH_REGISTRY_TOKEN := $(B64_ASSET_HOST_REGISTRY_PASSWORD)
# Values for the image pull secret
GH_RU := $(shell echo -n "$(B64_ASSET_HOST_REGISTRY_USERNAME)" | base64)
GH_SET_REG := cat -
GH_REG_TOKEN := $(ASSET_HOST_REGISTRY_PASSWORD)
endif

## Self-host KPT overrides
## ----------------------------------------------------------------------------|
APP_REGISTRY_SKIPTLSVERIFY ?= true
APP_REGISTRY_MIRROR ?= $(ASSET_HOST_REGISTRY_URL)
APP_CATALOG ?= $(ASSET_HOST_APP_CATALOG)

GH_CATALOG_TOKEN ?= $(B64_ASSET_HOST_GIT_PASSWORD)
GH_CATALOG_USER ?= $(B64_ASSET_HOST_GIT_USERNAME)
YANG_REMOTE_URL ?= $(ASSET_HOST_ARTIFACTS_URL)
LLM_DB_REMOTE_URL ?= $(ASSET_HOST_ARTIFACTS_URL)
endif
# Close ifeq ($(USE_ASSET_HOST),1)
