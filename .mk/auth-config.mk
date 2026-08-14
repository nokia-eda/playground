CRED_LABEL_WIDTH ?= 22
AUTH_CRED_LENGTH ?= 32

RANDOMIZE_CREDENTIALS ?= 1

# Credential display labels (used by show-initial-credentials; keep within CRED_LABEL_WIDTH)
CRED_LABEL_EDA := EDA admin user
CRED_LABEL_IDENTITY := Keycloak admin user
CRED_LABEL_IDENTITY_DB := Identity db
CRED_LABEL_GIT := Git admin user

# Postgres db
CRED_IDENITIY_DB ?= $(BUILD)/cred-identity-db.seed
# Keycloak admin user
CRED_IDENTITY ?= $(BUILD)/cred-identity.seed
# CE + Incluster git
CRED_GIT ?= $(BUILD)/cred-git.seed
# EDA admin user
CRED_EDA ?= $(BUILD)/cred-eda.seed

# $1 is the file to generate
# $2 is the length of random alphanumeric string
# Prefer /dev/urandom when available. Fallback streams hex from $RANDOM (bash builtin;
# weaker entropy, fine for first-boot creds users are expected to rotate).
# The infinite loop keeps printf output flowing until head -c has enough bytes; a single
# printf emits too few characters, and the loop stops once head closes the pipe.
# Pipeline ends with || true because bash runs with -o pipefail: when head exits after
# reading enough bytes, upstream cat/printf gets SIGPIPE (exit 141), which is expected.
define seed-credential
{ \
	if [[ ! -f $(1) ]]; then															 \
		echo "--> INFO: Generating randomized credential for $(3)"						;\
		{																				 \
			if [[ -r /dev/urandom ]]; then												 \
				cat /dev/urandom														;\
			else																		 \
				while :; do printf '%04x%04x' $$RANDOM $$RANDOM; done					;\
			fi																			;\
		} | LC_ALL=C tr -dc 'A-Za-z0-9' | head -c $(2) | base64 -w 0 > $(1) || true		;\
	fi																					;\
}
endef

define show-credential
{	\
	if [[ ! -f $(1) ]]; then \
		echo "--> ERROR: Generated credential for $(2) does not exist, do you need to run make generate-credentials ?";\
	else \
		printf '    %-$(CRED_LABEL_WIDTH)s : %s\n' '$(2)' "$$(base64 -d < $(1))" ;\
	fi ;\
}
endef

.PHONY: generate-credentials
generate-credentials: | $(BUILD) ## Generate credentials for use on a fresh install
	@if [[ ! -d $(KPT_PKG) ]]; then (echo "--> ERROR: $(KPT_PKG) does not exist, do you need to run make download-pkgs ?" && exit 1) fi;
	@{	\
		if [[ "$(RANDOMIZE_CREDENTIALS)" -eq 1 ]]; then																	 \
			echo "--> INFO: Randomizing initial boot credentials"														;\
			$(call seed-credential,$(CRED_IDENITIY_DB),$(AUTH_CRED_LENGTH),$(CRED_LABEL_IDENTITY_DB))					;\
			$(call seed-credential,$(CRED_IDENTITY),$(AUTH_CRED_LENGTH),$(CRED_LABEL_IDENTITY))							;\
			$(call seed-credential,$(CRED_GIT),$(AUTH_CRED_LENGTH),$(CRED_LABEL_GIT))									;\
			$(call seed-credential,$(CRED_EDA),$(AUTH_CRED_LENGTH),$(CRED_LABEL_EDA))									;\
		fi																												;\
	}

.PHONY: clean-generated-credentials
clean-generated-credentials: ## Clean up the generated credentials
	rm -f $(CRED_IDENITIY_DB) $(CRED_IDENTITY) $(CRED_GIT) $(CRED_EDA)

.PHONY: show-generated-credentials
show-generated-credentials: ## Show the generated credentials that are used
	@echo "--> INFO: Listing generated credentials"
	@$(call show-credential,$(CRED_EDA),$(CRED_LABEL_EDA))
	@$(call show-credential,$(CRED_IDENTITY),$(CRED_LABEL_IDENTITY))
	@$(call show-credential,$(CRED_IDENITIY_DB),$(CRED_LABEL_IDENTITY_DB))
	@$(call show-credential,$(CRED_GIT),$(CRED_LABEL_GIT))
