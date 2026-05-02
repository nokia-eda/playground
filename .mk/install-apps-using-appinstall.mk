define BUILD_BULK_CRS
{	\
	export TEMPLATE=$(1)														;\
	export BULKCR=$(2)															;\
	export NS=$(3)																;\
	export WFNAME=$(4)															;\
	export OP=$(5)																;\
	cp -fv $${TEMPLATE} $${BULKCR} | $(INDENT_OUT)								;\
	echo "--> APPS: Creating appInstaller cr for $${OP} operation"				;\
	$(YQ) -i '.metadata.namespace = env(NS)' $${BULKCR}							;\
	$(YQ) -i '.metadata.name = env(WFNAME)' $${BULKCR}							;\
	$(YQ) -i '.spec.operation = env(OP)' $${BULKCR}								;\
	app_count=0																	;\
	for APP in $(APPS_INSTALL_LIST_BUILTIN); do									 \
		export single_app_cr=$(APPS_INSTALL_CRS)/$${APP}-app-installer-$${OP}-cr.yaml										;\
		if [ ! -f $${single_app_cr} ]; then echo "[ERROR] Could not find the app cr for $${single_app_cr}"  && exit 1; fi	;\
		$(YQ) -i '.spec.apps += (load(env(single_app_cr)).spec.apps[0])' $${BULKCR}											;\
		echo "--> APPS: Adding $${APP}"											;\
		app_count=$$((app_count + 1))											;\
	done																		;\
	echo "--> APPS: Created appInstaller cr for $${app_count} apps - $${BULKCR}";\
}
endef

# $(1) is the bulk appinstaller cr where we will add these apps
# $(2) is a space separated list of app-group=app-semver
define BUILD_BULK_CRS_ADDITIONAL_APPS
{	\
	export BULKCR=$(1)															;\
	export ADDITIONAL_APPS="$(2)"												;\
	export CATALOG_NAME=$(3)													;\
	if [[ -z "$${ADDITIONAL_APPS}" ]]; then exit 0; fi							;\
	app_count=0																	;\
	for APP in $${ADDITIONAL_APPS}; do											 \
		export name=$$(echo "$${APP}" | cut -f1 -d '=')							;\
		export ver=$$(echo "$${APP}" | cut -f2 -d '=')							;\
		if [[ -z "$${name}" ]]; then echo "[ERROR] Could not extract app name from tuple "$${APP}" did you follow name=version (no spaces) ?" && exit 1; fi ;\
		if [[ -z "$${ver}" ]]; then echo "[ERROR] Could not extract app version from tuple "$${APP}" did you follow name=version (no spaces) ?" && exit 1; fi ;\
		export appId="$${name}.eda.nokia.com"									;\
		export appVer="$${ver}"													;\
		echo "--> APPS: Adding $${name} - $${appVer}"							;\
		export app_cr="{\"appId\": \"$${appId}\", \"catalog\": \"$${CATALOG_NAME}\", \"version\": {\"type\": \"semver\", \"value\": \"$${appVer}\"}}";\
		$(YQ) -i --prettyPrint '.spec.apps += env(app_cr)' "$${BULKCR}"			;\
		app_count=$$((app_count + 1))											;\
	done																		;\
	echo "--> APPS: Added $${app_count} apps to appInstaller cr - $${BULKCR}";\
}
endef

define BUILD_BULK_UPGRADE_CRS
{	\
	export TEMPLATE=$(1)														;\
	export BULKCR=$(2)															;\
	export NS=$(3)																;\
	export WFNAME=$(4)															;\
	export OP=$(5)																;\
	export EXCLUDED_APPS=$(6)													;\
	export UPG_TYPE=$(7)														;\
	export CATALOG=$(8)															;\
	APP_INSTALL_LIST=$$($(KUBECTL) --namespace $${NS} get manifests.core.eda.nokia.com -o yaml | $(YQ) '.items.[].spec | select (.gitReference != "local") | .group' | tr '\n' ' ');\
	if [[ -z "$${APP_INSTALL_LIST}" ]]; then \
		echo "--> No installed manifests found in $${NS}" && exit 1				;\
	fi																			;\
	cp -fv $${TEMPLATE} $${BULKCR} | $(INDENT_OUT)								;\
	echo "--> APPS: Creating appInstaller cr for $${OP} operation"				;\
	$(YQ) -i '.metadata.namespace = env(NS)' $${BULKCR}							;\
	$(YQ) -i '.metadata.name = env(WFNAME)' $${BULKCR}							;\
	$(YQ) -i '.spec.operation = env(OP)' $${BULKCR}								;\
	app_count=1																	;\
	for APP in $${APP_INSTALL_LIST}; do											 \
		if [[ "$${EXCLUDED_APPS}" == *"$${APP}"* ]]; then 						 \
			echo "--> APPS: $${APP} is excluded from upgrade"					;\
			continue															;\
		fi																		;\
		if [[ "$${UPG_TYPE}" == "alias" ]]; then								 \
			app_version="latest"												;\
		elif [[ "$${UPG_TYPE}" == "semver" ]]; then								 \
			latest_app_tag=$$(git -C $${CATALOG} tag | grep $${APP} | sort -r | head -n1) ;\
			if [[ -z $${latest_app_tag} ]]; then								 \
				echo "--> APPS: $${APP} not found in the catalog, skipping"		;\
				continue														;\
			fi																	;\
			app_version=$$(echo $${latest_app_tag} | rev | cut -f1 -d'/' | rev)	;\
		else																	 \
			echo "--> APPS: Invalid upgrade type: $${UPG_TYPE}" && exit 1		;\
		fi																		;\
		export upg_cr="{\"appId\": \"$${APP}\", \"catalog\": \"eda-catalog-builtin-apps\", \"version\": {\"type\": \"$${UPG_TYPE}\", \"value\": \"$${app_version}\"}}";\
		$(YQ) -i --prettyPrint '.spec.apps += env(upg_cr)' "$${BULKCR}"			;\
		echo "--> APPS: Upgrading $${APP} to $${app_version}"					;\
		((app_count++))															;\
	done																		;\
	echo "--> APPS: Created appInstaller cr for $${app_count} apps - $${BULKCR}";\
}
endef

## $1 is the name of the workflow cr i.e .metadata.name
## $2 is the workflow cr itself, i.e the yaml file to k apply
## The @ suppressor is not here, its in the $(call ...) where the macro is called
define RUN_APP_WF
	{	\
		START=$$(date +%s)																			;\
		export WF_NAME=$(1)																			;\
		export WF_CR=$(2)																			;\
		export OP=$(3)																				;\
		export INFO_HEADER="--> APPS: [\033[1;34m$${WF_NAME}\033[0m]"								;\
		export FAIL_HEADER="--> APPS: [\033[0;31m$${WF_NAME}\033[0m]"								;\
		export PASS_HEADER="--> APPS: [\033[0;32m$${WF_NAME}\033[0m]"								;\
		$(KUBECTL) --namespace $(EDA_APPS_INSTALL_NAMESPACE) delete -f $${WF_CR} --ignore-not-found	;\
		echo -e "$${INFO_HEADER} Running operation: $${OP}"										;\
		$(KUBECTL) --namespace $(EDA_APPS_INSTALL_NAMESPACE) apply -f $${WF_CR} 2>&1 | $(INDENT_OUT);\
		MAX_WAIT=$(APP_INSTALL_TIMEOUT)																;\
		COUNT=0																						;\
		COMPLETED=0																					;\
		while [ $$COUNT -lt $$MAX_WAIT ]; do														 \
			state=$$($(KUBECTL) --namespace $(EDA_APPS_INSTALL_NAMESPACE) get appinstallers.appstore.eda.nokia.com $${WF_NAME} --no-headers -o=jsonpath='{.status.result}');\
			if [[ "$${state}" == "Completed" ]]; then												 \
				COMPLETED=1																			;\
				break																				;\
			elif [[ "$${state}" == "Failed" ]]; then												 \
				COMPLETED=0																			;\
				break																				;\
			fi																						;\
			COUNT=$$((COUNT + 1))																	;\
			sleep 1 																				;\
		done 																						;\
		if [ $$COMPLETED -ne 1 ] ; then																 \
			echo																					;\
			$(KUBECTL) --namespace $(EDA_APPS_INSTALL_NAMESPACE) get transactionresults -o yaml		;\
			$(KUBECTL) --namespace $(EDA_APPS_INSTALL_NAMESPACE) get appinstallers -o yaml			;\
			echo -e "$${FAIL_HEADER} Failed to $${OP}, did not reach Completed state in $${COUNT}s, it is in $${state}";\
			echo -e "$${FAIL_HEADER} Check the error logs using 'edactl workflow get <id>'"			;\
			exit 1 																					;\
		else																						 \
			echo -e "$${PASS_HEADER} Completed operation: $${OP} in $$(( $$(date +%s) - $$START ))s";\
			$(KUBECTL) --namespace $(EDA_APPS_INSTALL_NAMESPACE) delete -f $${WF_CR} --ignore-not-found 2>&1 | $(INDENT_OUT);\
		fi																							;\
	}
endef