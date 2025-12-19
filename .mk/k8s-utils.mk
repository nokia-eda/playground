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

# Macro: Wait till the pod in a deployment has reached till running state
# -----------------------------------------------------------------------------|
# $1 A nice small prefix to print an info message
# $2 label to use to retrieve the pod name
# $3 namespace where pod is running
define K8S_WAIT_FOR_POD_RUNNING
	{	\
		export POD_NAME=$$($(KUBECTL) --namespace $(3) get pod -l $(2) -o jsonpath="{.items[0].metadata.name}")			;\
		echo -n "--> $(1): Waiting for pod: $$POD_NAME to reach running state"											;\
		while [ "$$($(KUBECTL) --namespace $(3) get pod $${POD_NAME} -o jsonpath='{.status.phase}')" != "Running" ]; do	 \
			sleep 5																										;\
			echo -n "."																									;\
		done																											;\
		echo ""	&& echo "--> $(1): $${POD_NAME} is Running"																;\
	}
endef

.PHONY: restart-deployment
restart-deployment: | $(KUBECTL) ## Restart a deployment NS=<namespace> DEP=<name of deployment>
	@if [[ -z "$(NS)" ]]; then (echo "[ERROR] Please specify the namespace using NS=<namespace>" && exit 1) ; fi;
	@if [[ -z "$(DEP)" ]]; then (echo "[ERROR] Please specify the deployment using DEP=<deployment>" && exit 1) ; fi;
	@echo "--> INFO: restarting deployment $(NS)/$(DEP)"
	@$(call K8S_ROLLOUT_OP,$(NS),restart,deployment,$(DEP))

.PHONY: scale-deployment
scale-deployment: | $(KUBECTL) ## Scale DEP=<name> to NUM=<number> of replicas in namespace NS
	@if [[ -z "$(NS)" ]]; then (echo "[ERROR] Please specify the namespace using NS=<namespace>" && exit 1) ; fi;
	@if [[ -z "$(DEP)" ]]; then (echo "[ERROR] Please specify the deployment using DEP=<deployment>" && exit 1) ; fi;
	@if [[ -z "$(NUM)" ]]; then (echo "[ERROR] Please specify the number of replicas using NUM=<number>" && exit 1) ; fi;
	@echo "--> INFO: scaling deployment $(NS)/$(DEP) to replica count: $(NUM)"
	@$(KUBECTL) --namespace $(NS) scale deployment $(DEP) --replicas $(NUM) | $(INDENT_OUT)

scale-down-deployment: NUM=0
.PHONY: scale-down-deployment
scale-down-deployment: | scale-deployment ## Scale down a deployment DEP in namespace NS to zero replicas
