# Build/test entry points. Ralph's VERIFY step auto-detects this Makefile and
# runs `make test` to gate each iteration (Nim is not in ralph's built-in
# language list, so this Makefile is the bridge).

.PHONY: test build check clean

# Primary gate: compile + run the test suite via nimble.
test:
	nimble test

# Library packages have no `bin`, so "build" is a type-check of the barrel module.
build: check

check:
	nim check --hints:off --mm:orc src/spliney.nim

clean:
	rm -rf nimcache nimblecache htmldocs
