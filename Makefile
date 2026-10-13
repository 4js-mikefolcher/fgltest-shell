# fgltest-shell — build
#
# Compiles the library modules AND the two programs into the package directory
# com/fourjs/fgltest/shell/*.42m, then the example application and the
# self-tests.
#
# Requires GNU make, a configured Genero environment (fglcomp/fglform/fglrun on
# PATH) and fgltest, which `fglpkg install` puts under .fglpkg/ — the first
# `make` runs it when fgltest is not there yet. No shell scripts are used.
# Non-Unix shells can override the file ops, e.g.:
#   make RM="del /q"

FGLCOMP ?= fglcomp
FGLFORM ?= fglform
FGLRUN  ?= fglrun
FGLPKG  ?= fglpkg
# NB: GNU make predefines RM = rm -f, so use = (not ?=) to override it here;
# a command-line `make RM=...` still wins (command-line beats makefile).
RM       = rm -rf

PKGDIR  := com/fourjs/fgltest/shell
# Where `fglpkg install` merges the installed packages (fgltest's modules).
DEPDIR  := .fglpkg/merged
TESTDIR := tests
DEMODIR := examples/demo

# The project root (holding com/) and the installed packages must be on
# FGLLDPATH, so IMPORT FGL com.fourjs.fgltest.* resolves both fgltest's modules
# and this package's own, whatever the recipe's working directory. tests/ is
# on it too, so the self-test can import its fake driver.
export FGLLDPATH := $(CURDIR):$(CURDIR)/$(TESTDIR):$(CURDIR)/$(DEPDIR)$(if $(FGLLDPATH),:$(FGLLDPATH))

# Library modules in dependency order (IMPORT FGL needs deps compiled first).
# repl imports commands/recording/render; session imports protocol.
LIBMODS := words protocol commands recording render session options repl
# MAIN programs (compiled after the library they import).
PROGS   := fgltest_session fgltest_shell

.PHONY: all deps lib programs example tests check check-byte check-char test lint clean

all: lib programs example tests

# fgltest, at the version fglpkg-lock.json pins.
deps: $(DEPDIR)/com/fourjs/fgltest/core.42m

$(DEPDIR)/com/fourjs/fgltest/core.42m:
	$(FGLPKG) install

# Compile each package module in order into com/fourjs/fgltest/shell/.
lib: deps
	$(foreach m,$(LIBMODS),$(FGLCOMP) -M $(PKGDIR)/$(m).4gl &&) true

# The programs are MAIN modules with no PACKAGE line, so (unlike package
# modules) -M writes their .42m to the CWD, not beside the source — force the
# location with --output-dir so they land beside the library.
programs: lib
	$(foreach p,$(PROGS),$(FGLCOMP) -M --output-dir $(PKGDIR) $(PKGDIR)/$(p).4gl &&) true

# The example application the end-to-end test drives.
example:
	cd $(DEMODIR) && $(FGLFORM) -M contacts.per \
	  && $(FGLFORM) -M contact.per \
	  && $(FGLCOMP) -M demo.4gl

# Build fgltest-shell's own test suite (no PACKAGE line: --output-dir, as for
# the programs).
tests: lib
	$(FGLCOMP) -M --output-dir $(TESTDIR) $(TESTDIR)/fakedriver.4gl
	$(FGLCOMP) -M --output-dir $(TESTDIR) $(TESTDIR)/selftest.4gl

# Run fgltest-shell's own tests. Needs NO GGC engine, NO scenario server and NO
# application, so it runs anywhere the compiler does — this is the target CI
# gates on. They run twice, under each FGL_LENGTH_SEMANTICS: BYTE is Genero's
# default and CHAR a common setting, and string code that is right under one
# can split multibyte text under the other. They need a UTF-8 locale (as
# Genero does): without one the multibyte cases would pass vacuously, so
# selftest's first check fails instead.
check: check-byte check-char

check-byte: export FGL_LENGTH_SEMANTICS = BYTE
check-byte: tests
	$(FGLRUN) $(TESTDIR)/selftest

check-char: export FGL_LENGTH_SEMANTICS = CHAR
check-char: tests
	$(FGLRUN) $(TESTDIR)/selftest

# End to end: drive the demo application from a shell script, save what the
# shell recorded, then replay that file with fgltest; then drive it a command
# per call, as an AI agent would (--detach, --send, --stop). Unlike `check`,
# this needs the GGC toolkit on PATH (source $$FGLDIR/testing_utilities/ggc/envggc
# first); the shell and fgltest start and stop the scenario server themselves.
test: all
	$(FGLRUN) $(PKGDIR)/fgltest_shell --script $(DEMODIR)/demo.shell \
	  --save results/demo.actions.json --outdir results --workdir $(DEMODIR) demo
	$(FGLRUN) $(DEPDIR)/com/fourjs/fgltest/fgltest $(DEMODIR)/fgltest.json
	$(FGLRUN) $(PKGDIR)/fgltest_shell --detach --idle 120 --outdir results --workdir $(DEMODIR) demo
	$(FGLRUN) $(PKGDIR)/fgltest_shell --outdir results --send "action append" \
	  --send "fill formonly.c_name Mary" --send "action accept"
	$(FGLRUN) $(PKGDIR)/fgltest_shell --outdir results --json --send "assertRowCount contacts 4"
	$(FGLRUN) $(PKGDIR)/fgltest_shell --outdir results --send "save results/agent.actions.json"
	$(FGLRUN) $(PKGDIR)/fgltest_shell --outdir results --stop

# Validate the package manifest exactly as `fglpkg pack`/`publish` would.
lint:
	$(FGLPKG) lint

clean:
	$(RM) $(PKGDIR)/*.42m \
	  $(TESTDIR)/*.42m \
	  results \
	  $(DEMODIR)/*.42m $(DEMODIR)/*.42f
