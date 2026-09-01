## The @ suppressor is not here, its in the $(call ...) where the macro is called
define DESTROY_KPT_PACKAGE
	{	\
		echo -e "--> UNINSTALL: [\033[1;34m$2\033[0m] - Destroying kpt package"									;\
		pushd $1 &>/dev/null || (echo "[ERROR]: Failed to switch cwd to $2" && exit 1)							;\
		if [[ ! -f resourcegroup.yaml ]]; then																	 \
			echo -e "--> UNINSTALL: $(WARN) Did not find a resourcegroup.yaml, is this package initialized ?"	;\
		fi																										;\
		$(KPT) live destroy 2>&1 | $(INDENT_OUT)																;\
		popd &>/dev/null || (echo "[ERROR]: Failed to switch back from $2" && exit 1)							;\
		echo -e "--> UNINSTALL: [\033[0;32m$2\033[0m] - resources reconciled"									;\
	}
endef

# Remove the errant transactionpipeline CRD if found
define UNINSTALL_CRD_TP
	{	\
		export crd_name="transactionpipelines.core.eda.nokia.com"														;\
		found=$$($(KUBECTL) get crd -o yaml | $(YQ) '.items[].metadata.name | select(. == env(crd_name))')				;\
		if [[ -n "$${found}" ]]; then																					 \
			echo "--> INFO: Found $${crd_name}"																			;\
			hasShortNames=$$($(KUBECTL) get crds $${crd_name} -o yaml | $(YQ) '.spec.names | has("shortNames")')		;\
			if [[ "$${hasShortNames}" == "true" ]]; then																 \
				short_yaml=$$($(KUBECTL) get crd $${crd_name} -o yaml | $(YQ) '.spec.names.shortNames | sort')			;\
				len=$$(echo "$${short_yaml}" | $(YQ) 'length')															;\
				first=$$(echo "$${short_yaml}" | $(YQ) '.[0]')															;\
				second=$$(echo "$${short_yaml}" | $(YQ) '.[1]')															;\
				if [[ "$${len}" == "2" && "$${first}" == "pipelinerun" && "$${second}" == "plr" ]]; then				 \
					$(KUBECTL) delete customresourcedefinitions.apiextensions.k8s.io $${crd_name} --force 				;\
					echo "--> INFO: Removed $${crd_name}"																;\
				fi																										;\
			fi																											;\
		fi																												;\
	}
endef

.PHONY: uninstall-eda-core-ns
uninstall-eda-core-ns: | $(BASE) $(KPT) 
	@$(call DESTROY_KPT_PACKAGE,$(KPT_EXT_PKGS)/eda-core-ns,core-ns)

.PHONY: uninstall-external-package-fluentd
uninstall-external-package-fluentd: | $(BASE) $(KPT)
	@$(call DESTROY_KPT_PACKAGE,$(KPT_EXT_PKGS)/fluentd,fluentd)

.PHONY: uninstall-external-package-cert-manager
uninstall-external-package-cert-manager: | $(BASE) $(KPT)
	@$(call DESTROY_KPT_PACKAGE,$(KPT_EXT_PKGS)/cert-manager,cert-manager)

.PHONY: uninstall-external-package-csi-driver
uninstall-external-package-csi-driver: | $(BASE) $(KPT)
	@$(call DESTROY_KPT_PACKAGE,$(KPT_EXT_PKGS)/csi-driver,csi-driver)

.PHONY: uninstall-external-package-trust-manager
uninstall-external-package-trust-manager: | $(BASE) $(KPT)
	@$(call DESTROY_KPT_PACKAGE,$(KPT_EXT_PKGS)/trust-manager,trust-manager)

.PHONY: uninstall-external-package-git
uninstall-external-package-git: | $(BASE) $(KPT)
	@$(call DESTROY_KPT_PACKAGE,$(KPT_EXT_PKGS)/git,git)

.PHONY: uninstall-external-package-eda-issuer-root
uninstall-external-package-eda-issuer-root: | $(BASE) $(KPT)
	@$(call DESTROY_KPT_PACKAGE,$(KPT_EXT_PKGS)/eda-issuer-root,eda root issuer)

.PHONY: uninstall-external-package-eda-issuer-node
uninstall-external-package-eda-issuer-node: | $(BASE) $(KPT)
	@$(call DESTROY_KPT_PACKAGE,$(KPT_EXT_PKGS)/eda-issuer-node,eda node issuer)

.PHONY: uninstall-external-package-eda-issuer-api
uninstall-external-package-eda-issuer-api: | $(BASE) $(KPT)
	@$(call DESTROY_KPT_PACKAGE,$(KPT_EXT_PKGS)/eda-issuer-api,eda api issuer)

# If core version < 25.8 then remove known finalizers first
# $(if $(filter $(IS_EDA_CORE_LESSTHAN_258X),1),uninstall-finalizers,)
# but perhaps it is better to run it always
.PHONY: uninstall-eda-core
uninstall-eda-core: | $(BASE) $(KPT) $(KUBECTL) $(YQ) uninstall-finalizers ; $(info --> KPT: Removing EDA Core) @ ## Base uninstall of EDA in a cluster
	@echo "--> INFO: EDA_CORE_VERSION=$(EDA_CORE_VERSION)"
	@$(call DESTROY_KPT_PACKAGE,$(KPT_CORE),EDA-CORE)
	@$(call UNINSTALL_CRD_TP)

# Keep the old target around in case someone calls it
.PHONY: eda-uninstall-core
eda-uninstall-core: uninstall-eda-core

.PHONY: uninstall-eda-bootstrap
uninstall-eda-bootstrap:
	@$(call DESTROY_KPT_PACKAGE,$(KPT_PG),EDA-PLAYGROUND)

.PHONY: eda-stop-core
eda-stop-core: $(KUBECTL)
	@$(call EDACTL_CMD,$(EDA_PLATFORM_CMD) stop)

# These finalizers were removed in 25.8 but are present in older releases by the appstore controller
NUKE_FINALIZERS_LIST=
NUKE_FINALIZERS_LIST+=registries.appstore.eda.nokia.com
NUKE_FINALIZERS_LIST+=catalogs.appstore.eda.nokia.com

.PHONY: uninstall-finalizers
uninstall-finalizers: $(KUBECTL)
	@{	\
		for crd in $(NUKE_FINALIZERS_LIST); do																 \
			echo "--> INFO: Removing finalizers from $$crd"													;\
			crs=$$($(KUBECTL) -n $(EDA_CORE_NAMESPACE) get $$crd -o=jsonpath='{.items[0].metadata.name}')	;\
			for cr in $$crs; do 																			 \
				echo "          Processing $$cr"															;\
				$(KUBECTL) patch -n $(EDA_CORE_NAMESPACE) $$crd $$cr -p '{"metadata":{"finalizers":null}}' --type=merge | $(INDENT_OUT_MORE)	;\
			done																							;\
		done																								;\
	}