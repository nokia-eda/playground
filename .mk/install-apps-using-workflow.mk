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