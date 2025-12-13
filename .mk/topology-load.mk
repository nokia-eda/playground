## --------------------------------------------------------------------------------------------------------------------|
## Network Topologies
## --------------------------------------------------------------------------------------------------------------------|
## 25.12 and beyond

.PHONY: topology-load-using-workflow-wait-to-be-ready
topology-load-using-workflow-wait-to-be-ready: | eda-is-toolbox-ready
	@{	\
		TOOLBOX_POD=$$($(KUBECTL) --namespace $(EDA_CORE_NAMESPACE) get pod -l $(POD_LABEL_ET) -o jsonpath="{.items[0].metadata.name}")						;\
		echo -n "--> TOPO: Waiting to be ready ."																											;\
		k8s_node_profile_count=$$($(KUBECTL) -n $(EDA_USER_NAMESPACE) get nodeprofiles.core.eda.nokia.com -o go-template='{{printf "%d\n" (len  .items)}}')	;\
		edc_node_profile_count=0																															;\
		while [[ $${edc_node_profile_count} -ne $${k8s_node_profile_count} ]]; do																			 \
			sleep $(TIMEOUT_TOPO_LOAD_NP_CHECK)																												;\
			edc_node_profile_count=$$($(KUBECTL) -n $(EDA_CORE_NAMESPACE) exec $${TOOLBOX_POD} -- bash -c "$(EDACTL_BIN) query -n $(EDA_USER_NAMESPACE) '.namespace.resources.cr.core_eda_nokia_com.v1.nodeprofile fields [ count (metadata.name) ]' -o yaml | $(EDATOOLBOX_TOOLS)/yq .[0].[]");\
			echo -n "."																																		;\
		done																																				;\
		echo ""																																				;\
		echo "--> TOPO: Synced NodeProfiles ($${k8s_node_profile_count}/$${edc_node_profile_count})"														;\
	}

.PHONY: topology-load-using-workflow
topology-load-using-workflow: | $(BASE) $(KUBECTL) $(YQ) ## Load the cluster dut topology using a network topology workflow - use TOPO=<> make to override the default
	@{	\
		cr_name=$$($(YQ) '.metadata.name' $(TOPO))											;\
		echo "--> TOPO: Loading $${cr_name}"												;\
		$(KUBECTL) --namespace $(EDA_USER_NAMESPACE) delete -f $(TOPO) --ignore-not-found	;\
		$(KUBECTL) --namespace $(EDA_USER_NAMESPACE) apply -f $(TOPO)						;\
		has_workflow_id=false																;\
		echo -n "--> TOPO: waiting for workflow id ."										;\
		while [[ $${has_workflow_id} != "true" ]]; do										 \
			has_workflow_id=$$($(KUBECTL) --namespace $(EDA_USER_NAMESPACE)	get networktopologies.topologies.eda.nokia.com $${cr_name} -o jsonpath='{.metadata.annotations}' | $(YQ) '. | has ("workflows.core.eda.nokia.com/id")');\
			echo -n "."																		;\
			sleep $(TIMEOUT_TOPO_LOAD_GET_WORKFLOW_ID)										;\
		done																				;\
		echo ""																				;\
		workflow_id=$$($(KUBECTL) --namespace $(EDA_USER_NAMESPACE) get networktopologies.topologies.eda.nokia.com $${cr_name} -o jsonpath='{.metadata.annotations}' | $(YQ) '."workflows.core.eda.nokia.com/id"')	;\
		echo "--> TOPO: workflow id: $${workflow_id} - Follow status using 'edactl workflow get $${workflow_id}'"	;\
	}

.PHONY: topology-is-workflow-completed
topology-is-workflow-completed: | $(BASE) $(KUBECTL) $(YQ) eda-is-toolbox-ready ## Did the network topology workflow complete ? - use TOPO=<> make to override the default
	@{	\
		START=$$(date +%s)																																	;\
		TOPO_NAME=$$($(YQ) '.metadata.name' $(TOPO))																										;\
		TOOLBOX_POD=$$($(KUBECTL) --namespace $(EDA_CORE_NAMESPACE) get pod -l $(POD_LABEL_ET) -o jsonpath="{.items[0].metadata.name}")						;\
		workflow_id=$$($(KUBECTL) --namespace $(EDA_USER_NAMESPACE) get networktopologies.topologies.eda.nokia.com $${TOPO_NAME} -o jsonpath='{.metadata.annotations}' | $(YQ) '."workflows.core.eda.nokia.com/id"')	;\
		IS_IT_DONE=NO 																																		;\
		echo "--> TOPO: Waiting for $${TOPO_NAME} [workflow:$${workflow_id}] to be completed"																;\
		while [[ $${IS_IT_DONE} != "COMPLETED"	]]; do 																										 \
			CURRENT_STATE=$$($(KUBECTL) -n $(EDA_CORE_NAMESPACE) exec -it $${TOOLBOX_POD} -- bash -c "export TOPO_NAME=$${TOPO_NAME} && $(EDACTL_BIN) -n $(EDA_USER_NAMESPACE) query .namespace.workflows.topologies_eda_nokia_com.v1alpha1.networktopology -o yaml | $(EDATOOLBOX_TOOLS)/yq 'filter(.metadata.name == ( env(TOPO_NAME) )) | .[].workflowStatus.state'" | tr -d '\r')	;\
			IS_IT_DONE=$$(echo "$${CURRENT_STATE}" | tr '[:lower:]' '[:upper:]')																			;\
			echo "--> TOPO: $${TOPO_NAME} [workflow:$${workflow_id}] is $${IS_IT_DONE}"																		;\
			if [[ "$${IS_IT_DONE}" == "FAILED" ]] || [[ "$${IS_IT_DONE}" == "TERMINATED" ]]; then															 \
				$(KUBECTL) -n $(EDA_CORE_NAMESPACE) exec -it $${TOOLBOX_POD} -- bash -l -c "edactl -n $(EDA_USER_NAMESPACE) workflow get $${workflow_id}"	;\
				$(KUBECTL) -n $(EDA_CORE_NAMESPACE) exec -it $${TOOLBOX_POD} -- bash -l -c "edactl -n $(EDA_USER_NAMESPACE) workflow logs $${workflow_id}"	;\
				echo "[ERROR] TOPO: workflow:$${workflow_id} could not complete: $${IS_IT_DONE}"															;\
				exit 1																																		;\
			fi																																				;\
			sleep $(TIMEOUT_TOPO_LOAD_IS_IT_COMPLETED)																										;\
		done																																				;\
		echo "--> TOPO: $${TOPO_NAME} [workflow:$${workflow_id}] - took $$(( $$(date +%s) - $$START ))s"													;\
	}

## --------------------------------------------------------------------------------------------------------------------|
## Pre 25.12.x using configMaps
## --------------------------------------------------------------------------------------------------------------------|
##
.PHONY: topology-load-using-config-map
topology-load-using-config-map: | $(YQ) $(KUBECTL) ## Load a topology file TOPO=<file> using a configMap
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
		$(KUBECTL) --namespace $(EDA_CORE_NAMESPACE) exec -it $$POD_NAME -- bash -c "/app/api-server-topo -n $(EDA_USER_NAMESPACE)" | $(INDENT_OUT);\
	}
