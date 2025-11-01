## The @ suppressor is not here, its in the $(call ...) where the macro is called

# $1 is the namespace
# $2 is the operation - restart|create
# $3 is the kind - deployment | daemonset
# $4 is the resource
define K8S_ROLLOUT_OP
	{	\
		$(KUBECTL) --namespace $(1) rollout $(2) $(3) $(4) | $(INDENT_OUT)	;\
	}
endef

.PHONY: restart-deployment
restart-deployment: | $(KUBECTL) ## Restart a deployment NS=<namespace> DEP=<name of deployment>
	@if [[ -z "$(NS)" ]]; then (echo "[ERROR] Please specify the namespace using NS=<namespace>" && exit 1) ; fi;
	@if [[ -z "$(DEP)" ]]; then (echo "[ERROR] Please specify the deployment using DEP=<deployment>" && exit 1) ; fi;
	@echo "--> INFO: restarting deployment $(NS)/$(DEP)"
	@$(call K8S_ROLLOUT_OP,$(NS),restart,deployment,$(DEP))