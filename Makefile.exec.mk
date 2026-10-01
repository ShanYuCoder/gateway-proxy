# Exec vào container dev: make exec SVC=<alias> [CMD='...'] hoặc make exec <alias>
# Chi tiết alias: make exec-list  |  script: exec-into.sh

.PHONY: exec exec-list

exec-list:
	@bash "$(ROOT)/exec-into.sh" --list

# make exec SVC=fullsco  |  make exec fullsco  |  make exec SVC=fullsco CMD="php artisan migrate"
exec:
	@bash "$(ROOT)/exec-into.sh" "$(if $(SVC),$(SVC),$(firstword $(EXEC_ALIASES)))" $(CMD)

ifneq ($(filter exec,$(MAKECMDGOALS)),)
  EXEC_ALIASES := $(filter-out exec,$(MAKECMDGOALS))
  ifndef EXEC_ALIASES
    EXEC_ALIASES :=
  endif
  ifneq ($(EXEC_ALIASES),)
    $(EXEC_ALIASES):
	@:
  endif
endif
