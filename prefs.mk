# User preferences
# Options in this file override options specified on the command line
# and the default values specified in the Makefile.
# To enable an option simply uncomment a line and give it a value

# Cluster Name
# -----------------------------------------------------------------------------|
# The cluster name is the name of the k8s CR engineconfigs.core.eda.nokia.com
# CLUSTER_MEMBER_NAME := eda-01

# Namespace settings for eda components
# -----------------------------------------------------------------------------|
#
# EDA_CORE_NAMESPACE := eda-system
# EDA_USER_NAMESPACE := eda

# Version selector for eda packages
# -----------------------------------------------------------------------------|
# List core versions using        make ls-versions-core
# List catalog versions using     make ls-versions-apps
#
# EDA_CORE_VERSION := 25.4.1
# EDA_APPS_VERSION := 25.4.1

# KinD cluster options
# -----------------------------------------------------------------------------|
# Do not deploy the kind cluster
# Uncomment this variable to perform playground installation
# on an already available k8s cluster
# NO_KIND := yes

# Use a custom kind configuration file
# KIND_CONFIG_FILE := private/kind-ingress-config.yml

# Use a different kind cluster name
# KIND_CLUSTER_NAME := eda-demo2

# Do not install metallb as part of the kind cluster
# NO_LB := yes

# Use a custom k8s cluster API server address
# KIND_API_SERVER_ADDRESS := "10.1.2.3"

# Disable binding ports from the host to kind container for EXT_HTTPS_PORT
# A port forward will be launched instead
# NO_HOST_PORT_MAPPINGS := yes

# How do clients reach your cluster?
#  EXT_DOMAIN_NAME can also be set to an ipv4/6 address if no domain record
#  is present. In that case EXT_IPV4_ADDR = $(EXT_DOMAIN_NAME) or its ipv6
#  counterpart.
# -----------------------------------------------------------------------------|

# EXT_DOMAIN_NAME = "<Your domain name or ip address>"
# EXT_HTTP_PORT = "<Port for http access>"
# EXT_HTTPS_PORT = "<Port for https access>"
# EXT_IPV4_ADDR = "<LB IP or external route>"
# EXT_IPV6_ADDR = "<Same thing but in ipv6>"

# EDA CX options
# -----------------------------------------------------------------------------|
# Do not deploy simulator nodes in CX for the TopoNode resources
# set to false when connecting hardware nodes to the cluster
# or when simulators nodes are deployed by another system.
# When set to false, the topology-load make target will be skipped and
# no TopoNode resources will be created.
# SIMULATE := false

# Don't prefer dual stack services if possible in the configured cluster.
# -----------------------------------------------------------------------------|

# SINGLESTACK_SVCS = false

# Proxy vars specific to the cluster nodes
# rather than the host machine that the make is running from
# -----------------------------------------------------------------------------|

# HTTPS_PROXY ?= ""
# HTTP_PROXY ?= ""
# NO_PROXY ?= ""
# https_proxy ?= ""
# http_proxy ?= ""
# no_proxy ?= ""

# OpenAI API key
# -----------------------------------------------------------------------------|

# LLM_API_KEY ?= ""

# KPT Core setters config file
#  A path to the apply-setters function config file that holds the values
#  you intend to apply to the EDA Core packages.
#  See config/kpt-core-setters.yml for an example.
# -----------------------------------------------------------------------------|

# KPT_SETTERS_FILE := private/kpt-setters.yml

# External packages options
# -----------------------------------------------------------------------------|

# do not install fluentd + fluent-bit
# Set to "yes" to use your own logging aggregators and collectors
# NO_FLUENTD_INSTALL := yes

# do not install cert-manager.
# Set to "yes" when you have your own cert-manager in a "cert-manager" namespace
# It will still verify the cert-manager deployment and webhook is ready
# NO_CERT_MANAGER_INSTALL := yes

# do not install cert-manager CSI driver.
# Set to "yes" when the host cluster already has a cert-manager CSI driver installed.
# NO_CSI_DRIVER_INSTALL := yes

# do not install trust-manager.
# Set to "yes" when you have your own trust-manager that is listening to secrets
# in the "EDA_CORE_NAMESPACE" namespace.
# NO_TRUSTMGR_INSTALL := yes

# do not install the provided in-cluster Git servers.
# Set to "yes" when you have your own set of Git servers.
# Use the kpt setter "GIT_SERVERS : []" to specify a custom set of git servers
# NO_GOGS_INSTALL := yes

# do not install EDA root issuer
# Set to "yes" when bringing your own.
# NO_EDA_ISSUER_ROOT_INSTALL := yes

# do not install EDA node issuer
# Set to "yes" when bringing your own.
# NO_EDA_ISSUER_NODE_INSTALL := yes

# do not install EDA issuer API.
# Set to "yes" when the installing EDA in a vcluster.
# NO_EDA_ISSUER_API_INSTALL := yes

# KPT init options
# -----------------------------------------------------------------------------|

# Ignore if a package was already init'd against a cluster (resourcegroup.yaml)
# Use --force to overwrite an existing inventory
# KPT_LIVE_INIT_FORCE := 1

# Add --inventory-policy=adopt to live apply, this will allow kpt to adopt
# already applied *unmanaged* resources that the kpt package is trying to
# clear, it will update/reconcile any differences.
# KPT_INVENTORY_ADOPT := 1

# PORT FORWARD options
# -----------------------------------------------------------------------------|
# Name of the eda-api service to port forward to, default: eda-api
# For use when there are multiple eda-api loadbalancer services
# PORT_FORWARD_TO_API_SVC := eda-api

# Tools options
# -----------------------------------------------------------------------------|
# Repo to use to fetch edabuilder binary from. Defaults to nokia-eda/edabuilder
# EDABUILDER_SRC := my-org/edabuilder

# Enable self-host operation via an eda-asset-host
# -----------------------------------------------------------------------------|
# Enable this to operate in self-host mode
# USE_ASSET_HOST := 1

# This can be FQDN, DNS or IP where the asset host can be reached
# Do not add transport schemes (http/https/ssh) to ASSET_HOST
# ASSET_HOST := eda-assets-01

# Specify auth
# ASSET_HOST_GIT_USERNAME := ""
# ASSET_HOST_GIT_PASSWORD := ""
# ASSET_HOST_ARTIFACTS_USERNAME := ""
# ASSET_HOST_ARTIFACTS_PASSWORD := ""