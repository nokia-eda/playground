# User preferences
# Options in this file override options specified on the command line
# and the default values specified in the Makefile.
# To enable an option simply uncomment a line and give it a value

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