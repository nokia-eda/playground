SHELL = /usr/bin/env bash -o pipefail
.SHELLFLAGS = -ec

TOP_DIR := $(abspath $(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
BASE=$(CURDIR)

-include $(TOP_DIR)/prefs.mk

## Top level options
BUILD ?= build
KIND_CLUSTER_NAME ?= eda-demo
TOPO ?= $(TOP_DIR)/topology/3-nodes-srl.yaml
TOPO_EMPTY ?= $(TOP_DIR)/topology/00-delete-all-nodes.yaml
LOGS_DEST ?= /tmp/eda-support/logs-$(shell date +"%Y%m%d%H%M%S")
ARCH_QUERY := $(shell uname -m)
ifeq ($(ARCH_QUERY), x86_64)
	ARCH := amd64
else
	ARCH := $(ARCH_QUERY)
endif

OS_QUERY := $(shell uname -s)
ifeq ($(OS_QUERY), Darwin)
	XARGS_CMD ?= xargs -S 2048
else
	XARGS_CMD ?= xargs
endif

EXT_DOMAIN_NAME ?= $(shell hostname -f)
EXT_HTTP_PORT ?= 9200
EXT_HTTPS_PORT ?= 9443
EXT_IPV4_ADDR ?= $(shell ip -4 addr show scope global | grep inet | grep -Eo '([0-9]*\.){3}[0-9]*' | head -1)
EXT_IPV6_ADDR ?= $(shell ip -6 addr show scope global | grep inet6 | sed -e 's/^.*inet6 \([^ ]*\)\/.*$$/\1/;t;d' | head -1)
SINGLESTACK_SVCS ?= false
HTTPS_PROXY ?= ""
HTTP_PROXY ?= ""
NO_PROXY ?= ""
https_proxy ?= ""
http_proxy ?= ""
no_proxy ?= ""
LLM_API_KEY ?= ""

# i.e Darwin / Linux
UNAME := $(shell uname)
# Lowercase - sane version
OS := $(shell echo "$(UNAME)" | tr '[:upper:]' '[:lower:]')

APPLY_SETTER_IMG=ghcr.io/srl-labs/kpt-apply-setters:0.1.1

CORE_IMAGE_REGISTRY=ghcr.io/nokia-eda
SRL_IMAGE_REGISTRY=ghcr.io/nokia

# Set the SRL Image to the arm variant if we're on arm64
ifeq ($(ARCH), arm64)
  SRL_24_7_1_GHCR=$(SRL_IMAGE_REGISTRY)/srlinux:24.7.1-arm-preview
else
  SRL_24_7_1_GHCR=$(SRL_IMAGE_REGISTRY)/srlinux:24.7.1-330
endif

## Level 2 options
TOOLS ?= $(BASE)/tools
KPT_PKG ?= $(BASE)/eda-kpt
CATALOG ?= $(BASE)/catalog
K8S_HELM ?= $(BASE)/connect-k8s-helm-charts
TIMEOUT_NODE_READY ?= 600s

CFG := $(TOP_DIR)/configs

KPT_EXT_PKGS := $(KPT_PKG)/eda-external-packages
KPT_CORE := $(KPT_PKG)/eda-kpt-base
KPT_PLAYGROUND := $(KPT_PKG)/eda-kpt-playground

CM_WH_YML := $(KPT_PKG)/eda-external-packages/webhook-tests/cert-manager-webhook-ready-check.yaml

GET_SVC_CIDR=$(KUBECTL) cluster-info dump | grep -m 1 service-cluster-ip-range | sed 's/ //g' | sed -ne 's/\"--service-cluster-ip-range=\(.*\)\",/\1/p'
GET_POD_CIDR=$(KUBECTL) cluster-info dump | grep -m 1 cluster-cidr | sed 's/ //g' | sed -ne 's/\"--cluster-cidr=\(.*\)\",/\1/p'

## Tools:
KIND := $(TOOLS)/kind
KUBECTL := $(TOOLS)/kubectl
KPT ?= $(TOOLS)/kpt
K9S ?= $(TOOLS)/k9s
YQ ?= $(TOOLS)/yq
CURL := curl --silent --fail --show-error

## Where to get things:

### Access token
GH_RO_TOKEN := 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

### Eda components
EDA_KPT_PKG_SRC := https://$(GH_RO_TOKEN)@github.com/nokia-eda/kpt.git
CATALOG_PKG_SRC := https://$(GH_RO_TOKEN)@github.com/nokia-eda/catalog.git
K8S_HELM_PKG_SRC := https://$(GH_RO_TOKEN)@github.com/nokia-eda/connect-k8s-helm-charts.git

### Tools
KIND_SRC := https://kind.sigs.k8s.io/dl/v0.17.0/kind-$(OS)-$(ARCH)
KUBECTL_SRC := https://dl.k8s.io/release/v1.25.3/bin/$(OS)/$(ARCH)/kubectl
KPT_SRC := https://github.com/GoogleContainerTools/kpt/releases/download/v1.0.0-beta.44/kpt_$(OS)_$(ARCH)
# K9s uses the uname directly in its package name
K9S_SRC := https://github.com/derailed/k9s/releases/download/v0.32.5/k9s_$(UNAME)_$(ARCH).tar.gz
YQ_SRC := https://github.com/mikefarah/yq/releases/download/v4.42.1/yq_$(OS)_$(ARCH)

## Create working directories

$(BUILD): | $(BASE); $(info --> Creating a build dir: $(BUILD))
	@mkdir -p $(BUILD)

$(TOOLS): | $(BASE); $(info --> Creating a tools dir: $(TOOLS))
	@mkdir -p $(TOOLS)

## Download all the tools
.PHONY: download-tools
download-tools: | $(BASE) $(KIND) $(KUBECTL) $(KPT) $(YQ) $(K9S) ## Download required and useful tools

define download-bin
	if test ! -f $(1); then $(CURL) -Lo $(1) $(2) >/dev/null && chmod a+x $(1); fi
endef

# $1 - Output binary name to extract from the archive
# $2 - URL to download it from
# $3 - where should tar extract this file ?
# $4 - What is the path/filename inside the archive ?
# $5 - tar options if its compressed etc
# This does assume that $(1) on disk is equal to $(3)/$(4) where $(4) is the path+name of the bin inside the archive
define download-bin-from-archive
	if test ! -f $(1); then $(CURL) -L --output - $(2) | tar -x$(5) -C $(3) $(4) && chmod +x $(1); fi 
endef

$(KIND): | $(BASE) $(TOOLS) ; $(info --> TOOLS: Ensuring kind is present in $(KIND))
	@$(call download-bin,$(KIND),$(KIND_SRC))

$(KUBECTL): | $(BASE) $(TOOLS) ; $(info --> TOOLS: Ensuring kubectl is present in $(KUBECTL))
	@$(call download-bin,$(KUBECTL),$(KUBECTL_SRC))

$(KPT): | $(BASE) $(TOOLS) ; $(info --> TOOLS: Ensuring kpt is present in $(KPT))
	@$(call download-bin,$(KPT),$(KPT_SRC))

$(K9S): | $(BASE) $(TOOLS) ; $(info --> TOOLS: Ensuring k9s is present in $(K9S))
	@$(call download-bin-from-archive,$(K9S),$(K9S_SRC),$(TOOLS),k9s,z)

$(YQ): | $(BASE) $(TOOLS) ; $(info --> TOOLS: Ensuring yq is present in $(YQ))
	@$(call download-bin,$(YQ),$(YQ_SRC))


## Download the kpt package and the catalog
$(KPT_PKG): | $(BASE) $(KPT) ; $(info --> KPT: Ensuring the kpt pkg is present in $(KPT_PKG))
#	$(KPT) pkg get $(EDA_KPT_PKG_SRC) $(KPT_PKG)
	git clone $(EDA_KPT_PKG_SRC) $(KPT_PKG)

$(CATALOG): | $(BASE); $(info --> APPS: Ensuring the apps catalog is present in $(CATALOG))
	git clone $(CATALOG_PKG_SRC) $(CATALOG)

.PHONY: download-pkgs
download-pkgs: | $(KPT_PKG) $(CATALOG) ## Download the eda-kpt and apps catalog 

.PHONY: update-pkgs
update-pkgs: ## Fetch eda kpt and catalog updates
#	$(KPT) pkg update $(KPT_PKG)
	git -C $(KPT_PKG) pull
	git -C $(CATALOG) pull
	git -C $(CATALOG) pull --tags --force

$(K8S_HELM): | $(BASE); $(info --> CONNECT K8S HELM CHARTS: Ensuring the Connect K8s Helm charts are present in $(K8S_HELM))
	git clone $(K8S_HELM_PKG_SRC) $(K8S_HELM)

.PHONY: download-connect-k8s-helm-charts
download-connect-k8s-helm-charts: | $(K8S_HELM) ## Download the connect-k8s-helm-charts

.PHONY: update-connect-k8s-helm-charts
update-connect-k8s-helm-charts: ## Fetch connect-k8s-helm-charts updates
	git -C $(K8S_HELM) pull

.PHONY: login-registry
login-registry: ## Log in to the core image registries
	@{	\
		echo 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 | \
 		docker login $(CORE_IMAGE_REGISTRY) -u nokia-eda-bot --password-stdin ;\
	}


# Optionally pre-pull the images for kind-based clusters
# where you may load the images to the kind cluster to avoid
# pulling them from the repo

RELEASE_TAG=24.8.1-rc

CONTAINER_IMAGES := \
	"$(CORE_IMAGE_REGISTRY)/core/eda-keycloak:$(RELEASE_TAG)" \
	"$(CORE_IMAGE_REGISTRY)/core/eda-postgres:$(RELEASE_TAG)" \
	"$(CORE_IMAGE_REGISTRY)/core/gogs:0.13.0" \
	"$(CORE_IMAGE_REGISTRY)/core/config-engine:$(RELEASE_TAG)" \
	"$(CORE_IMAGE_REGISTRY)/ext/sig-storage/csi-node-driver-registrar:v2.10.0" \
	"$(CORE_IMAGE_REGISTRY)/ext/sig-storage/livenessprobe:v2.12.0" \
	"$(CORE_IMAGE_REGISTRY)/ext/jetstack/cert-manager-csi-driver:v0.8.0" \
	"$(CORE_IMAGE_REGISTRY)/ext/jetstack/cert-manager-cainjector:v1.14.4" \
	"$(CORE_IMAGE_REGISTRY)/core/api-server:$(RELEASE_TAG)" \
	"$(CORE_IMAGE_REGISTRY)/core/appstore-server:$(RELEASE_TAG)" \
	"$(CORE_IMAGE_REGISTRY)/core/artifact-server:$(RELEASE_TAG)" \
	"$(CORE_IMAGE_REGISTRY)/core/bootstrap-server:$(RELEASE_TAG)" \
	"$(CORE_IMAGE_REGISTRY)/core/cx:$(RELEASE_TAG)" \
	"$(CORE_IMAGE_REGISTRY)/core/flow-engine:$(RELEASE_TAG)" \
	"$(CORE_IMAGE_REGISTRY)/core/state-aggregator:$(RELEASE_TAG)" \
	"$(CORE_IMAGE_REGISTRY)/core/state-controller:$(RELEASE_TAG)" \
	"$(CORE_IMAGE_REGISTRY)/core/state-engine:$(RELEASE_TAG)" \
	"$(CORE_IMAGE_REGISTRY)/core/eda-toolbox:$(RELEASE_TAG)" \
	"$(CORE_IMAGE_REGISTRY)/core/fluentd:v1.17.0-debian-1.0" \
	"$(CORE_IMAGE_REGISTRY)/core/fluent-bit:3.0.7-amd64" \
	"$(CORE_IMAGE_REGISTRY)/core/cxdp:$(RELEASE_TAG)" \
	"$(CORE_IMAGE_REGISTRY)/core/npp:$(RELEASE_TAG)" \
	"$(SRL_24_7_1_GHCR)"

.PHONY: pull-images
pull-images: | login-registry ## Pull eda core images
	@for image in $(CONTAINER_IMAGES); do \
	docker pull $$image & \
	done; wait

.PHONY: kind-load-images
kind-load-images: ## Load eda core images into the kind cluster
	@for image in $(CONTAINER_IMAGES); do \
	$(KIND) load docker-image $$image --name $(KIND_CLUSTER_NAME) & \
	done; wait

## Cluster launch

.PHONY: kind
kind: cluster cluster-wait-for-node-ready $(if $(NO_LB),,metallb) ## Launch a single node KinD cluster (K8S inside Docker)

.PHONY: cluster
cluster: | $(KIND) $(KUBECTL); $(info --> KIND: Ensuring control-plane exists)
	@{	\
		MATCHED=0																			;\
		for cluster in $$($(KIND) get clusters); do 										 \
			if [[ "$${cluster}" == "$(KIND_CLUSTER_NAME)" ]]; then							 \
				MATCHED=1																	;\
			fi																				;\
		done																				;\
		if [[ "$${MATCHED}" == "0" ]]; then													 \
			$(KIND) create cluster --name $(KIND_CLUSTER_NAME)	--config $(CFG)/kind.yaml	;\
		else																				 \
			echo "--> KIND: cluster named $(KIND_CLUSTER_NAME) exists"						;\
		fi																					;\
	}

.PHONY: cluster-wait-for-node-ready
cluster-wait-for-node-ready: | $(BASE) ; $(info --> KIND: wait for k8s node to be ready) @ ## Wait for the k8s cp to declare the node to be ready
	@{	\
		START=$$(date +%s)																;\
		$(KUBECTL) wait --for=condition=Ready nodes --all --timeout=$(TIMEOUT_NODE_READY)	;\
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

LB_CFG_SRC := $(CFG)/metallb.yaml

define KPT_SET_CM
apiVersion: v1
kind: ConfigMap
metadata:
  name: apply-setters-fn-config
data:
  LB_IP_POOLS: |
    - $1.255.0/24
    - $2:ffff:ffff:ffff:ffff/120
endef

.PHONY: metallb-config
metallb-config: | $(BASE) $(KPT) ; $(info --> LB: Applying metallb config) @ ## Apply metallb address pools
	$(eval KIND_SUBNETS=$(shell docker network inspect -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}' kind))
	$(eval KIND_SUBNET=$(shell echo "$(KIND_SUBNETS)" | tr ' ' '\n' | grep -v ':' | head -n 1 | awk -F'.' '{print $$1 "." $$2}'))
	$(eval KIND_SUBNET6=$(shell echo "$(KIND_SUBNETS)" | tr ' ' '\n' | grep ':' | head -n 1 | awk -F':' '{print $$1 ":" $$2 ":" $$3 ":" $$4}'))
	@echo "--> LB: Detected IPv4 Subnet: $(KIND_SUBNET)"
	@echo "--> LB: Detected IPv6 Subnet: $(KIND_SUBNET6)"
	@cat $(LB_CFG_SRC) | $(KPT) fn eval - --image $(APPLY_SETTER_IMG) --truncate-output=false --output unwrap -- LB_IP_POOLS="[$(KIND_SUBNET).255.0/24, $(KIND_SUBNET6):ffff:ffff:ffff:ffff/120]" | $(KUBECTL) apply -f - | sed 's/^/    /'

.PHONY: metallb
metallb: | $(BASE) $(KUBECTL) metallb-operator metallb-config ## Load the metallb loadbalancer into the cluster

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
		$(KUBECTL) wait deployment trust-manager -n cert-manager --for condition=Available=True --timeout=120s 2>&1 | sed 's/^/    /'	;\
		echo "--> TRUST: Deployment is ready - took: $$(( $$(date +%s) - $$START ))s" 												;\
	}

POD_SELECTOR_GOGS ?= git
POD_LABEL_GOGS ?= eda.nokia.com/app=$(POD_SELECTOR_GOGS)

.PHONY: git-is-init-done
git-is-init-done: | $(BASE) $(KUBECTL) ; $(info --> GOGS: Waiting for pod init to complete) @ ## Has the gogs pod done launching ? Halt till then
	@$(KUBECTL) exec -it $$($(KUBECTL) get pods -l eda.nokia.com/app=$(POD_SELECTOR_GOGS) --no-headers -o=jsonpath='{.items[*].metadata.name}') -- bash -c 'until [[ -f /data/eda-git-init.done ]]; do echo "--> GOGS: waiting for init.done ... - $$(date)" && sleep 1; done; echo "--> GOGS: Reached init.done!"'

define INSTALL_KPT_PACKAGE
	{	\
		echo -e "--> INSTALL: [\033[1;34m$2\033[0m] - Applying kpt package"				;\
		pushd $1 &>/dev/null || (echo "[ERROR]: Failed to switch cwd to $2" && exit 1)	;\
		$(KPT) live init --force 2>&1 | sed 's/^/    /'										;\
		$(KPT) live apply 2>&1 | sed 's/^/    /'											;\
		popd &>/dev/null || (echo "[ERROR]: Failed to switch back from $2" && exit 1)	;\
		echo -e "--> INSTALL: [\033[0;32m$2\033[0m] - Applied and reconciled package"	;\
	}
endef

.PHONY: load-image-pull-secret
load-image-pull-secret: | $(BASE) $(KUBECTL) $(KPT_PKG)
	@$(KUBECTL) apply -f $(TOP_DIR)/eda-kpt/eda-kpt-base/secrets/gh-core-pkgs.yaml 2>&1 | sed 's/^/    /'

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
INSTALL_EXTERNAL_PACKAGE_LIST += load-image-pull-secret
INSTALL_EXTERNAL_PACKAGE_LIST += install-external-package-fluentd
INSTALL_EXTERNAL_PACKAGE_LIST += install-external-package-cert-manager
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
install-external-packages: | $(BASE) $(INSTALL_EXTERNAL_PACKAGE_LIST) ## Install external components for EDA core (cert/trust-manager,fluentd,csi,gogs,CA's)


.PHONY: eda-configure-core
eda-configure-core: ## Configure the EDA core deployment before launching
	@{	\
		echo "--> KPT:CORE: Setting cluster parameters in engineconfig"	;\
		pushd $(KPT_CORE) &> /dev/null || (echo "[ERROR] Could not change cwd to $(KPT_CORE) from $$(pwd)" && exit 1);\
		export cluster_pod_cidr=$$($(GET_POD_CIDR))				;\
		export cluster_svc_cidr=$$($(GET_SVC_CIDR))				;\
		export HTTPS_PROXY=$(HTTPS_PROXY)						;\
		export HTTP_PROXY=$(HTTP_PROXY)							;\
		export NO_PROXY="$(NO_PROXY),$${cluster_pod_cidr},$${cluster_svc_cidr},.local,.svc,eda-git,eda-git-replica";\
		export https_proxy=$(https_proxy)						;\
		export http_proxy=$(http_proxy)							;\
		export no_proxy="$(no_proxy),$${cluster_pod_cidr},$${cluster_svc_cidr},.local,.svc,eda-git,eda-git-replica";\
		$(KPT) fn eval --image $(APPLY_SETTER_IMG) \
		--truncate-output=false \
		-- SINGLESTACK_SVCS=$(SINGLESTACK_SVCS) \
		LLM_API_KEY=$(LLM_API_KEY) \
		EXT_DOMAIN_NAME=$(EXT_DOMAIN_NAME) \
		EXT_HTTP_PORT=$(EXT_HTTP_PORT) \
		EXT_HTTPS_PORT=$(EXT_HTTPS_PORT) \
		EXT_IPV4_ADDR=$(EXT_IPV4_ADDR) \
		EXT_IPV6_ADDR=$(EXT_IPV6_ADDR) \
		HTTPS_PROXY=$${HTTPS_PROXY} \
		HTTP_PROXY=$${HTTP_PROXY} \
		NO_PROXY=$${NO_PROXY} \
		https_proxy=$${https_proxy} \
		http_proxy=$${http_proxy} \
		no_proxy=$${no_proxy} 2>&1 | sed 's/^/    /' ;\
		popd &> /dev/null || (echo "[ERROR] Could not change cwd to $(KPT_CORE) from $$(pwd)" && exit 1);\
	}

.PHONY: eda-install-core
eda-install-core: | $(BASE) $(KPT) ; $(info --> KPT: Launching EDA) @ ## Base install of EDA in a cluster
	@$(call INSTALL_KPT_PACKAGE,$(KPT_CORE),EDA CORE)

ENGINECONFIG_CR_NAME ?= engine-config
.PHONY: is-ce-first-commit-done
is-ce-first-commit-done: | $(BASE) $(KUBECTL); $(info --> CE: Blocking until engine has first commit) @ ## Block until the config engine has processed its first commit
	@{	\
		counter=0																											;\
		while true; do																										 \
			if [[ "$$($(KUBECTL) get engineconfig $(ENGINECONFIG_CR_NAME) -o=jsonpath='{.status.run-status}')" = "Started" ]]; then	 \
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

CE_CHILDREN_DEPLOYMENTS_LIST=
CE_CHILDREN_DEPLOYMENTS_LIST += eda-api
CE_CHILDREN_DEPLOYMENTS_LIST += eda-appstore
CE_CHILDREN_DEPLOYMENTS_LIST += eda-asvr
CE_CHILDREN_DEPLOYMENTS_LIST += eda-bsvr
CE_CHILDREN_DEPLOYMENTS_LIST += eda-cx
CE_CHILDREN_DEPLOYMENTS_LIST += eda-fe
CE_CHILDREN_DEPLOYMENTS_LIST += eda-keycloak
CE_CHILDREN_DEPLOYMENTS_LIST += eda-postgres
CE_CHILDREN_DEPLOYMENTS_LIST += eda-sa
CE_CHILDREN_DEPLOYMENTS_LIST += eda-sc
CE_CHILDREN_DEPLOYMENTS_LIST += eda-toolbox

define WAIT_FOR_DEP
	{	\
		START=$$(date +%s)													;\
		INFO_1=0															;\
		INFO_2=0															;\
		while true; do														 \
			if ! $(KUBECTL) get deployments.apps $1 --no-headers &> /dev/null ; then \
				if [[ $${INFO_1} -ne 1 ]]; then 							 \
					echo -e "--> LAUNCH: [\033[1;35m$1\033[0m] Waiting for deployment to be created";\
					INFO_1=1												;\
				fi															;\
				sleep 2													;\
			else															 \
				avail_rep=$$($(KUBECTL) get deployments.apps $1 -ojsonpath='{.status.availableReplicas}')	;\
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

.PHONY: eda-is-core-deployment-ready
eda-is-core-deployment-ready: | $(BASE) $(KUBECTL) ## Wait for all of the core pods to launch and be ready
	@$(call WAIT_FOR_DEP,eda-ce)

	@echo $(CE_CHILDREN_DEPLOYMENTS_LIST) | tr ' ' '\n' | \
		$(XARGS_CMD) -P 11 -I {} bash -c '$(call WAIT_FOR_DEP,{})'

.PHONY: eda-is-core-ready
eda-is-core-ready: | eda-is-core-deployment-ready is-ce-first-commit-done is-apps-registry-reachable is-apps-catalog-operational ## Flight checks if core is ready


.PHONY: eda-uninstall-core
eda-uninstall-core: | $(BASE) $(KPT) ; $(info --> KPT: Removing EDA core services) ## Destroy the core kpt deployment
	@{	\
		pushd $(KPT_CORE)				;\
		$(KPT) live destroy				;\
		echo "--> KPT: Core resources reconciled";\
		popd							;\
	}

APPS_INSTALL_CRS := $(CATALOG)/install-crs
APP_VENDOR := nokia
APP_INSTALL_TIMEOUT ?= 600

define INSTALL_APP
	{	\
		START=$$(date +%s)																	;\
		export APP=$(1)																		;\
		echo -e "--> INSTALL:APP: [\033[1;34m$${APP}\033[0m] Installing"					;\
		$(KUBECTL) apply -f $(APPS_INSTALL_CRS)/$${APP}-install-cr.yaml 2>&1 | sed "s/^/    /"	;\
		MAX_WAIT=$(APP_INSTALL_TIMEOUT)														;\
		COUNT=0																				;\
		INSTALLED=0																			;\
		ATTEMPTED_INSTALL=0																	;\
		while [ $$COUNT -lt $$MAX_WAIT ]; do												 \
			state=$$($(KUBECTL) get appinstalls.appstore.eda.nokia.com $$APP.$(APP_VENDOR) --no-headers -o=jsonpath='{.status.Stage}');\
			if [[ "$${state}" == "Installed" ]]; then										 \
				INSTALLED=1																	;\
				break																		;\
			fi																				;\
			ATTEMPTED_INSTALL=1																;\
			COUNT=$$((COUNT + 1))															;\
			sleep 1 																		;\
		done 																				;\
		if [ $$INSTALLED -ne 1 ] ; then														 \
			echo																			;\
			$(KUBECTL) get transactionresults -o yaml										;\
			$(KUBECTL) get appinstalls -o yaml												;\
			echo "--> INSTALL:APP: [\033[0;31m$${APP}\033[0m] Failed to install did not reach installed state in $${COUNT}s, it is in $${state}" ;\
			exit 1 																			;\
		else																				 \
			echo -e "--> INSTALL:APP: [\033[0;32m$${APP}\033[0m] Installed in $$(( $$(date +%s) - $$START ))s" ;\
		fi																					;\
	}
endef

# Apps that need to be installed in a specific order
APPS_INSTALL_SEQ_LIST_BUILTIN=
APPS_INSTALL_SEQ_LIST_BUILTIN += core
APPS_INSTALL_SEQ_LIST_BUILTIN += appstore

APPS_INSTALL_LIST_BUILTIN=
APPS_INSTALL_LIST_BUILTIN += anomalies
APPS_INSTALL_LIST_BUILTIN += bootstrap
APPS_INSTALL_LIST_BUILTIN += components
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

NUMBER_OF_PARALLEL_APP_INSTALLS ?= 20

.PHONY: is-apps-catalog-operational
is-apps-catalog-operational: ## Can the EDA AppStore catalog be reached ?
	@{	\
		START=$$(date +%s)													;\
		MAX_WAIT=$(APP_INSTALL_TIMEOUT)										;\
		COUNT=0																;\
		INSTALLED=0															;\
		reachable="false"													;\
		resource="eda-catalog-builtin-apps"									;\
		echo -e "--> APP: [\033[1;34m$${resource}\033[0m] Waiting for catalog to be operational";\
		while [ $$COUNT -lt $$MAX_WAIT ]; do								 \
			reachable=$$($(KUBECTL) get catalogs.appstore.eda.nokia.com $${resource} --no-headers -o=jsonpath='{.status.operational}');\
			if [[ "$${reachable}" == "true" ]]; then						 \
				INSTALLED=1													;\
				break														;\
			fi																;\
			COUNT=$$((COUNT + 1))											;\
			sleep 1 														;\
		done 																;\
		if [ $$INSTALLED -ne 1 ] ; then										 \
			echo															;\
			$(KUBECTL) get catalogs.appstore.eda.nokia.com $${resource} -o yaml			;\
			echo "--> [ERROR] APP catalog - $${resource} is not operational" && exit 1	;\
			exit 1 															;\
		else																 \
			echo -e "--> APP: [\033[0;32m$${resource}\033[0m] Catalog is operational in $$(( $$(date +%s) - $$START ))s" ;\
		fi																	;\
	}

.PHONY: is-apps-registry-reachable
is-apps-registry-reachable: ## Can the EDA AppStore image registry be reached ?
	@{	\
		START=$$(date +%s)													;\
		MAX_WAIT=$(APP_INSTALL_TIMEOUT)										;\
		COUNT=0																;\
		INSTALLED=0															;\
		reachable="false"													;\
		resource="eda-apps-registry"										;\
		echo -e "--> APP: [\033[1;34m$${resource}\033[0m] Waiting for app registry to be reachable";\
		while [ $$COUNT -lt $$MAX_WAIT ]; do								 \
			reachable=$$($(KUBECTL) get registries.appstore.eda.nokia.com $${resource} --no-headers -o=jsonpath='{.status.reachable}');\
			if [[ "$${reachable}" == "true" ]]; then						 \
				INSTALLED=1													;\
				break														;\
			fi																;\
			COUNT=$$((COUNT + 1))											;\
			sleep 1 														;\
		done 																;\
		if [ $$INSTALLED -ne 1 ] ; then										 \
			echo															;\
			$(KUBECTL) get registries.appstore.eda.nokia.com $${resource} -o yaml	;\
			echo "--> [ERROR] APP catalog - $${resource} is not reachable" && exit 1;\
			exit 1 															;\
		else																 \
			echo -e "--> APP: [\033[0;32m$${resource}\033[0m] Registry is reachable in $$(( $$(date +%s) - $$START ))s" ;\
		fi																	;\
	}

.PHONY: eda-install-apps
eda-install-apps: | $(BASE) $(CATALOG) $(KUBECTL) is-apps-catalog-operational is-apps-registry-reachable ## Install EDA apps from the appstore catalog
	@echo "--> INSTALL:APP: Installing apps from catalog $(CATALOG)"
	@{	\
		for app in $(APPS_INSTALL_SEQ_LIST_BUILTIN)	;\
		do									 \
			$(call INSTALL_APP,$$app)		;\
		done 								;\
	}

	@echo $(APPS_INSTALL_LIST_BUILTIN) | tr ' ' '\n' | \
		$(XARGS_CMD) -P $(NUMBER_OF_PARALLEL_APP_INSTALLS) -I {} bash -c '$(call INSTALL_APP,{})'

.PHONY: eda-configure-playground
eda-configure-playground:
	@{	\
		pushd $(KPT_PLAYGROUND) &> /dev/null || (echo "[ERROR] Could not change cwd to $(KPT_PLAYGROUND) from $$(pwd)" && exit 1)	;\
		echo "--> KPT: Setting SRL Image: $(SRL_24_7_1_GHCR)"																		;\
		$(KPT) fn eval --image $(APPLY_SETTER_IMG) --truncate-output=false -- SRL_24_7_1_GHCR=$(SRL_24_7_1_GHCR) 2>&1 | sed 's/^/    /' ;\
		popd &> /dev/null || (echo "[ERROR] Could not change cwd to $(KPT_PLAYGROUND) from $$(pwd)" && exit 1)						;\
	}

.PHONY: eda-bootstrap
eda-bootstrap: | $(BASE) $(KPT) eda-configure-playground; $(info --> KPT: Bootstrapping EDA) @ ## Load allocation pools, secrets, node profiles...
	@$(call INSTALL_KPT_PACKAGE,$(KPT_PLAYGROUND),EDA PLAYGROUND)

.PHONY: template-topology
template-topology:  ## Create topology config-map from the topology input
	$(YQ) eval-all '{"apiVersion": "v1","kind": "ConfigMap","metadata": {"name": "topo-config"},"data": {"eda.json": (. | tojson)}} ' $(TOPO)


.PHONY: topology-load
topology-load:  ## Load a topology file TOPO=<file>
	@{	\
		echo "--> TOPO: JSON Processing"					;\
		$(YQ) eval-all '{"apiVersion": "v1","kind": "ConfigMap","metadata": {"name": "topo-config"},"data": {"eda.json": (. | tojson)}} ' $(TOPO) | $(KUBECTL) apply -f -				;\
		echo "--> TOPO: config created in cluster"			;\
		export POD_NAME=$$($(KUBECTL) get pod -l eda.nokia.com/app=apiserver -o jsonpath="{.items[0].metadata.name}"); \
		echo "--> TOPO: Using POD_NAME: $$POD_NAME"			;\
		echo "--> TOPO: Checking if $$POD_NAME is Running"	;\
		while [ "$$($(KUBECTL) get pod $$POD_NAME -o jsonpath='{.status.phase}')" != "Running" ]; do \
			echo "--> TOPO: Waiting for $$POD_NAME to be in Running state...";\
			sleep 5											;\
		done												;\
		$(KUBECTL) exec -it $$POD_NAME -- bash -c "/app/api-server-topo" | sed 's/^/    /';\
	}

.PHONY: start-ui-port-forward
start-ui-port-forward: | $(KUBECTL) ## Start a port from the eda api service to the host at port 9200
	@{	\
		echo "--> Exposing the UI to the host across the kind container boundary"																	;\
		CLUSTER_EXT_DOMAIN_NAME=$$($(KUBECTL) get engineconfigs.core.eda.nokia.com engine-config -ojsonpath='{.spec.cluster.external.domainName}')	;\
		CLUSTER_EXT_HTTPS_PORT=$$($(KUBECTL) get engineconfigs.core.eda.nokia.com engine-config -ojsonpath='{.spec.cluster.external.httpsPort}')	;\
		echo "--> The UI can be accessed using https://$${CLUSTER_EXT_DOMAIN_NAME}:$${CLUSTER_EXT_HTTPS_PORT}"										;\
                port_forward_cmd="$(KUBECTL) port-forward service/eda-api --address 0.0.0.0 $${CLUSTER_EXT_HTTPS_PORT}:443" ;\
                if [[ $${CLUSTER_EXT_HTTPS_PORT} -eq 443 ]]; then \
		port_forward_cmd="sudo -E $${port_forward_cmd}" ;\
		fi ;\
		eval $$port_forward_cmd ;\
	}


.PHONY: open-toolbox
open-toolbox: ## Log into the toolbox pod
	$(KUBECTL) exec -it $$($(KUBECTL) get pods -l eda.nokia.com/app=eda-toolbox -o=jsonpath='{.items[*].metadata.name}') -- env "TERM=xterm-256color" bash

.PHONY: e9s
e9s: ## Run e9s application
	$(KUBECTL) exec -it $$($(KUBECTL) get pods -l eda.nokia.com/app=eda-toolbox -o=jsonpath='{.items[*].metadata.name}') -- env "TERM=xterm-256color" /eda/tools/e9s

# NODE CLI access
define NODE_CLI
	$(KUBECTL) exec -it $$($(KUBECTL) get pods -l cx-pod-name=$(1) -o=jsonpath='{.items[*].metadata.name}') -- bash -c 'sudo sr_cli' -l
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
	$(KUBECTL) exec -it $$($(KUBECTL) get pods -l $(POD_LABEL_FD) --no-headers -o=jsonpath='{.items[*].metadata.name}') -- bash -c "lnav /var/log/eda/*"

.PHONY: logs-collect
logs-collect: | $(KUBECTL) ## Get the logs from the cluster LOGS_DEST=<custom location>
	@{	\
		export TO=$(LOGS_DEST)	;\
		mkdir -p $${TO}			;\
		set +e ;\
		echo "--> This is collected from $(TOP_DIR)" >> $${TO}/top-dir ;\
		echo "--> Cluster name is $(KIND_CLUSTER_NAME)" >> $${TO}/cluster-name ;\
		$(KUBECTL) cp $$($(KUBECTL) get pods -l $(POD_LABEL_FD) --no-headers -o=jsonpath='{.items[*].metadata.name}'):/var/log/eda "$${TO}"/	;\
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


.PHONY: try-eda
try-eda: | download-tools download-pkgs update-pkgs $(if $(NO_KIND),,kind) install-external-packages eda-configure-core eda-install-core eda-is-core-ready eda-install-apps eda-bootstrap topology-load
	@echo "--> INFO: EDA is launched"
	@echo "--> INFO: The UI port forward can be started using 'make start-ui-port-forward'"

.PHONY: help
help:  ## Show the help menu
	@sed -ne 's/^\([^[:space:]]*\):.*##/\1\t|\t/p' $(MAKEFILE_LIST) | sort | column -t -s $$'\t'
