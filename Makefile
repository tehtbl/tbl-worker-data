################################################################################
# Variables
################################################################################

# shell to use
SHELL := /bin/bash

# Config Dirs
MY_DIR := $(shell echo $(shell cd "$(shell dirname "${BASH_SOURCE[0]}" )" && pwd ))

# Required execs
REQUIRED_EXECUTABLES := gpg grep jq

################################################################################
# Macros / Methods
################################################################################

MY_SECRETS_DIR := $(MY_DIR)/.secrets
MY_SECRETS_FILE_LIST := $(MY_SECRETS_DIR)/files.txt

# check for executables in $PATH
K := $(foreach exec,$(REQUIRED_EXECUTABLES),\
        $(if $(shell which $(exec)),some string,$(error "Program $(exec) not in PATH")))

# based on: https://stackoverflow.com/questions/10858261/abort-makefile-if-variable-not-set
check_defined = \
    $(strip $(foreach 1,$1, \
        $(call __check_defined,$1,$(strip $(value 2)))))
__check_defined = \
    $(if $(value $1),, \
      $(error Undefined $1$(if $2, ($2))))

################################################################################
# Makefile TARGETS
################################################################################

.DEFAULT_GOAL := help

#
# Help
#
# based to https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
.PHONY: help list
help: ## This help
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

list: ## list all Makefile targets
	@make -qp | grep -E '^[[:alnum:]_]+' | grep -Ev ' :?= ' | grep -E ':' | cut -d ':' -f 1 | sort | uniq

#
# clean up tasks
#
.PHONY: clean clean_all
clean: ## removes build dir and others
	for i in $(shell cat $(MY_SECRETS_FILE_LIST)); do rm -f "$$i"; done

clean_all: clean ## deep clean all

#
# check for env variables
#
.PHONY: check_ENV check_TBL_PW_WORKER_DATA
check_ENV: check_TBL_PW_WORKER_DATA ## check for all environment vars

check_TBL_PW_WORKER_DATA:
	@$(call check_defined, TBL_PW_WORKER_DATA, please set TBL_PW_WORKER_DATA before proceeding)

#
# de-/encrypting
#
.PHONY: check_gitignore decrypt_all_files encrypt_all_files
check_gitignore:
	@cd $(MY_DIR) && \
		while IFS= read -r myfile; do grep -i $$myfile $(MY_DIR)/.gitignore > /dev/null || { echo; echo "ATTENTION: $$myfile not in .gitignore !!!"; echo; }; done < $(MY_SECRETS_FILE_LIST)

decrypt_all_files: check_gitignore check_ENV ## decrypt all files
	@cd $(MY_DIR) && \
		while IFS= read -r myfile; \
		do \
		  echo "decrypting $$myfile"; \
		  echo "${TBL_PW_WORKER_DATA}" | (gpg --batch --decrypt --passphrase-fd 0 --output $(MY_DIR)/$$myfile "$(MY_DIR)/$$myfile".mysecret 2> /dev/null || true); \
		done < $(MY_SECRETS_FILE_LIST)

encrypt_all_files: check_gitignore check_ENV ## (re-)encrypt all files
	@cd $(MY_DIR) && \
		while IFS= read -r myfile; \
		do \
		  echo "encrypting $$myfile"; \
		  test -f $(MY_DIR)/$$myfile || { echo "$$myfile does not exist ... aborting."; exit -1; }; \
		  echo "${TBL_PW_WORKER_DATA}" | gpg --yes --batch --armor --symmetric --passphrase-fd 0 --output "$(MY_DIR)/$$myfile".mysecret $(MY_DIR)/$$myfile 2> /dev/null ; \
		  rm -f $(MY_DIR)/$$myfile; \
		done < $(MY_SECRETS_FILE_LIST)

#
# make worker release
#
.PHONY: evaluate_env_file worker_check worker_pull docker_login worker_shell worker_clean
# evaluate_env_file: decrypt_all_files
evaluate_env_file:
ifeq (,$(wildcard $(MY_DIR)/.env))
	@$(MAKE) decrypt_all_files
endif
	@$(eval include $(MY_DIR)/.env)
	@export $(shell grep -iv "^#" $(MY_DIR)/.env)
