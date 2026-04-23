# Makefile for autoslip-roam
# Build, test, and install the package and documentation

# ==============================================================================
# Configuration
# ==============================================================================

# Emacs executable
EMACS ?= emacs

# Package files
PACKAGE = autoslip-roam.el
TEST_FILE = test-autoslip-roam.el

# Documentation
TEXI_FILE = autoslip-roam.texi
INFO_FILE = autoslip-roam.info

# Installation directories
PREFIX ?= /usr/local
INFODIR ?= $(PREFIX)/share/info
LISPDIR ?= $(PREFIX)/share/emacs/site-lisp/autoslip-roam

# User-specific installation (no sudo required)
USER_EMACS_DIR ?= $(HOME)/.emacs.d
USER_INFODIR ?= $(USER_EMACS_DIR)/info
USER_LISPDIR ?= $(USER_EMACS_DIR)/site-lisp/autoslip-roam

# Custom package directories for dependencies
CUSTOM_PACKAGE_DIR = ~/e30fewpackages/elpa
STANDARD_PACKAGE_DIR = ~/.emacs.d/elpa

# ==============================================================================
# Auto-detect Dependencies
# ==============================================================================

ORG_ROAM_PATH := $(shell find $(CUSTOM_PACKAGE_DIR) $(STANDARD_PACKAGE_DIR) -maxdepth 1 -type d -name "org-roam-[0-9]*" 2>/dev/null | head -1)
EMACSQL_PATH := $(shell find $(CUSTOM_PACKAGE_DIR) $(STANDARD_PACKAGE_DIR) -maxdepth 1 -type d -name "emacsql-[0-9]*" 2>/dev/null | head -1)
MAGIT_SECTION_PATH := $(shell find $(CUSTOM_PACKAGE_DIR) $(STANDARD_PACKAGE_DIR) -maxdepth 1 -type d -name "magit-section-[0-9]*" 2>/dev/null | head -1)
DASH_PATH := $(shell find $(CUSTOM_PACKAGE_DIR) $(STANDARD_PACKAGE_DIR) -maxdepth 1 -type d -name "dash-[0-9]*" 2>/dev/null | head -1)
S_PATH := $(shell find $(CUSTOM_PACKAGE_DIR) $(STANDARD_PACKAGE_DIR) -maxdepth 1 -type d -name "s-[0-9]*" 2>/dev/null | head -1)
F_PATH := $(shell find $(CUSTOM_PACKAGE_DIR) $(STANDARD_PACKAGE_DIR) -maxdepth 1 -type d -name "f-[0-9]*" 2>/dev/null | head -1)
COMPAT_PATH := $(shell find $(CUSTOM_PACKAGE_DIR) $(STANDARD_PACKAGE_DIR) -maxdepth 1 -type d -name "compat-[0-9]*" 2>/dev/null | head -1)
COND_LET_PATH := $(shell find $(CUSTOM_PACKAGE_DIR) $(STANDARD_PACKAGE_DIR) -maxdepth 1 -type d -name "cond-let-[0-9]*" 2>/dev/null | head -1)
LLAMA_PATH := $(shell find $(CUSTOM_PACKAGE_DIR) $(STANDARD_PACKAGE_DIR) -maxdepth 1 -type d -name "llama-[0-9]*" 2>/dev/null | head -1)
SEQ_PATH := $(shell find $(CUSTOM_PACKAGE_DIR) $(STANDARD_PACKAGE_DIR) -maxdepth 1 -type d -name "seq-[0-9]*" 2>/dev/null | head -1)

# Build load path
LOAD_PATH = -L .
ifneq ($(COMPAT_PATH),)
    LOAD_PATH += -L $(COMPAT_PATH)
endif
ifneq ($(COND_LET_PATH),)
    LOAD_PATH += -L $(COND_LET_PATH)
endif
ifneq ($(LLAMA_PATH),)
    LOAD_PATH += -L $(LLAMA_PATH)
endif
ifneq ($(SEQ_PATH),)
    LOAD_PATH += -L $(SEQ_PATH)
endif
ifneq ($(DASH_PATH),)
    LOAD_PATH += -L $(DASH_PATH)
endif
ifneq ($(S_PATH),)
    LOAD_PATH += -L $(S_PATH)
endif
ifneq ($(F_PATH),)
    LOAD_PATH += -L $(F_PATH)
endif
ifneq ($(EMACSQL_PATH),)
    LOAD_PATH += -L $(EMACSQL_PATH)
endif
ifneq ($(MAGIT_SECTION_PATH),)
    LOAD_PATH += -L $(MAGIT_SECTION_PATH)
endif
ifneq ($(ORG_ROAM_PATH),)
    LOAD_PATH += -L $(ORG_ROAM_PATH)
endif
LOAD_PATH += -L $(CUSTOM_PACKAGE_DIR) -L $(STANDARD_PACKAGE_DIR)

# Batch mode flags
BATCH_FLAGS = --batch --no-init-file $(LOAD_PATH)

# ==============================================================================
# Targets
# ==============================================================================

.PHONY: all test test-batch test-unit test-integration test-edge test-regression \
        test-perf test-verbose test-specific test-quick test-interactive \
        check-deps compile compile-tests compile-all lint checkdoc check \
        info install install-info install-lisp install-user install-info-user \
        uninstall uninstall-user clean distclean help list-tests count-tests

all: compile info

# ==============================================================================
# Dependency Checking
# ==============================================================================

check-deps: ## Check that all dependencies are available
	@echo "Checking dependencies..."
	@if [ -z "$(ORG_ROAM_PATH)" ]; then \
		echo "ERROR: org-roam not found"; \
		echo "  Install with: M-x package-install RET org-roam RET"; \
		exit 1; \
	else \
		echo "✓ org-roam: $(ORG_ROAM_PATH)"; \
	fi
	@if [ -n "$(EMACSQL_PATH)" ]; then echo "✓ emacsql: $(EMACSQL_PATH)"; fi
	@if [ -n "$(MAGIT_SECTION_PATH)" ]; then echo "✓ magit-section: $(MAGIT_SECTION_PATH)"; fi
	@if [ -n "$(DASH_PATH)" ]; then echo "✓ dash: $(DASH_PATH)"; fi
	@if [ -n "$(S_PATH)" ]; then echo "✓ s: $(S_PATH)"; fi
	@if [ -n "$(F_PATH)" ]; then echo "✓ f: $(F_PATH)"; fi
	@if [ -n "$(COMPAT_PATH)" ]; then echo "✓ compat: $(COMPAT_PATH)"; fi
	@if [ -n "$(COND_LET_PATH)" ]; then echo "✓ cond-let: $(COND_LET_PATH)"; else echo "⚠ cond-let: not found (may need: M-x package-install RET cond-let)"; fi
	@if [ -n "$(LLAMA_PATH)" ]; then echo "✓ llama: $(LLAMA_PATH)"; else echo "⚠ llama: not found (may need: M-x package-install RET llama)"; fi
	@echo "Dependency check complete."

# ==============================================================================
# Testing
# ==============================================================================

test: check-deps test-batch ## Run all tests (default test target)

test-batch: ## Run all tests in batch mode
	@echo "Running all tests..."
	$(EMACS) $(BATCH_FLAGS) \
		-l ert \
		-l $(PACKAGE) \
		-l $(TEST_FILE) \
		-f ert-run-tests-batch-and-exit

test-unit: ## Run unit tests only
	@echo "Running unit tests..."
	$(EMACS) $(BATCH_FLAGS) \
		-l ert \
		-l $(PACKAGE) \
		-l $(TEST_FILE) \
		--eval '(ert-run-tests-batch-and-exit "^test-\\(parse\\|extract\\|next-letter\\|validate\\|suggest\\|find\\|index\\)")'

test-integration: ## Run integration tests only
	@echo "Running integration tests..."
	$(EMACS) $(BATCH_FLAGS) \
		-l ert \
		-l $(PACKAGE) \
		-l $(TEST_FILE) \
		--eval '(ert-run-tests-batch-and-exit "^test-\\(insert\\|bidirectional\\|mode\\)")'

test-edge: ## Run edge case tests only
	@echo "Running edge case tests..."
	$(EMACS) $(BATCH_FLAGS) \
		-l ert \
		-l $(PACKAGE) \
		-l $(TEST_FILE) \
		--eval '(ert-run-tests-batch-and-exit "^test-edge")'

test-regression: ## Run regression tests only
	@echo "Running regression tests..."
	$(EMACS) $(BATCH_FLAGS) \
		-l ert \
		-l $(PACKAGE) \
		-l $(TEST_FILE) \
		--eval '(ert-run-tests-batch-and-exit "^test-regression")'

test-perf: ## Run performance tests only
	@echo "Running performance tests..."
	$(EMACS) $(BATCH_FLAGS) \
		-l ert \
		-l $(PACKAGE) \
		-l $(TEST_FILE) \
		--eval '(ert-run-tests-batch-and-exit "^test-perf")'

test-verbose: ## Run all tests with verbose output
	@echo "Running tests with verbose output..."
	$(EMACS) $(BATCH_FLAGS) \
		-l ert \
		-l $(PACKAGE) \
		-l $(TEST_FILE) \
		--eval '(setq ert-batch-print-level 10)' \
		--eval '(setq ert-batch-print-length 100)' \
		-f ert-run-tests-batch-and-exit

test-specific: ## Run a specific test (use TEST=test-name)
	@echo "Running test: $(TEST)..."
	$(EMACS) $(BATCH_FLAGS) \
		-l ert \
		-l $(PACKAGE) \
		-l $(TEST_FILE) \
		--eval "(ert-run-tests-batch-and-exit '$(TEST))"

test-quick: ## Run quick test suite (parsing and validation)
	@echo "Running quick tests..."
	$(EMACS) $(BATCH_FLAGS) \
		-l ert \
		-l $(PACKAGE) \
		-l $(TEST_FILE) \
		--eval '(ert-run-tests-batch-and-exit "^test-\\(parse\\|validate\\)")'

test-interactive: ## Run tests interactively in Emacs
	@echo "Running tests interactively..."
	$(EMACS) $(LOAD_PATH) \
		-l ert \
		-l $(PACKAGE) \
		-l $(TEST_FILE) \
		--eval "(ert t)"

# ==============================================================================
# Compilation
# ==============================================================================

compile: $(PACKAGE:.el=.elc) ## Byte-compile the package

$(PACKAGE:.el=.elc): $(PACKAGE)
	@echo "Byte-compiling $(PACKAGE)..."
	$(EMACS) $(BATCH_FLAGS) \
		--eval '(setq byte-compile-error-on-warn t)' \
		-f batch-byte-compile $(PACKAGE)

compile-tests: $(TEST_FILE:.el=.elc) ## Byte-compile the test file

$(TEST_FILE:.el=.elc): $(TEST_FILE) $(PACKAGE)
	@echo "Byte-compiling $(TEST_FILE)..."
	$(EMACS) $(BATCH_FLAGS) \
		-l $(PACKAGE) \
		-f batch-byte-compile $(TEST_FILE)

compile-all: compile compile-tests ## Compile all Emacs Lisp files

# ==============================================================================
# Documentation
# ==============================================================================

info: $(INFO_FILE) ## Build Info documentation

$(INFO_FILE): $(TEXI_FILE)
	@echo "Building Info documentation..."
	@if command -v makeinfo >/dev/null 2>&1; then \
		makeinfo --no-split $(TEXI_FILE) -o $(INFO_FILE); \
		echo "Generated $(INFO_FILE)"; \
	else \
		echo "ERROR: makeinfo not found. Install texinfo package."; \
		echo "  macOS: brew install texinfo"; \
		echo "  Debian/Ubuntu: sudo apt-get install texinfo"; \
		echo "  RHEL/CentOS: sudo yum install texinfo"; \
		exit 1; \
	fi

# ==============================================================================
# Linting
# ==============================================================================

checkdoc: ## Check documentation strings
	@echo "Running checkdoc..."
	$(EMACS) $(BATCH_FLAGS) \
		-l $(PACKAGE) \
		--eval '(checkdoc-file "$(PACKAGE)")'

lint: checkdoc ## Run all linting checks

check: lint compile-all test ## Run all quality checks

# ==============================================================================
# Installation (System-wide, requires sudo)
# ==============================================================================

install: install-lisp install-info ## Install package and documentation system-wide

install-lisp: compile ## Install Emacs Lisp files system-wide
	@echo "Installing Emacs Lisp files to $(LISPDIR)..."
	install -d $(LISPDIR)
	install -m 644 $(PACKAGE) $(LISPDIR)/
	install -m 644 $(PACKAGE:.el=.elc) $(LISPDIR)/ 2>/dev/null || true
	@echo "Installed to $(LISPDIR)"

install-info: info ## Install Info documentation system-wide
	@echo "Installing Info documentation to $(INFODIR)..."
	install -d $(INFODIR)
	install -m 644 $(INFO_FILE) $(INFODIR)/
	@if command -v install-info >/dev/null 2>&1; then \
		install-info --info-dir=$(INFODIR) $(INFODIR)/$(INFO_FILE) 2>/dev/null || true; \
		echo "Registered $(INFO_FILE) in Info directory"; \
	else \
		echo "Warning: install-info not found, manual dir entry may be needed"; \
	fi
	@echo "Installed to $(INFODIR)"
	@echo ""
	@echo "Access in Emacs with: C-h i d m Autoslip Roam RET"

uninstall: ## Uninstall from system directories
	@echo "Uninstalling from system directories..."
	rm -f $(LISPDIR)/$(PACKAGE)
	rm -f $(LISPDIR)/$(PACKAGE:.el=.elc)
	rmdir $(LISPDIR) 2>/dev/null || true
	@if command -v install-info >/dev/null 2>&1; then \
		install-info --delete --info-dir=$(INFODIR) $(INFODIR)/$(INFO_FILE) 2>/dev/null || true; \
	fi
	rm -f $(INFODIR)/$(INFO_FILE)
	@echo "Uninstallation complete"

# ==============================================================================
# Installation (User-local, no sudo required)
# ==============================================================================

install-user: install-lisp-user install-info-user ## Install to user directories (no sudo)

install-lisp-user: compile ## Install Emacs Lisp files to user directory
	@echo "Installing Emacs Lisp files to $(USER_LISPDIR)..."
	mkdir -p $(USER_LISPDIR)
	cp $(PACKAGE) $(USER_LISPDIR)/
	cp $(PACKAGE:.el=.elc) $(USER_LISPDIR)/ 2>/dev/null || true
	@echo "Installed to $(USER_LISPDIR)"
	@echo ""
	@echo "Add to your init.el:"
	@echo '  (add-to-list '\''load-path "$(USER_LISPDIR)")'

install-info-user: info ## Install Info documentation to user directory
	@echo "Installing Info documentation to $(USER_INFODIR)..."
	mkdir -p $(USER_INFODIR)
	cp $(INFO_FILE) $(USER_INFODIR)/
	@echo "Installed to $(USER_INFODIR)"
	@echo ""
	@echo "Add to your init.el:"
	@echo '  (add-to-list '\''Info-additional-directory-list "$(USER_INFODIR)")'
	@echo ""
	@echo "Then access in Emacs with: C-h i d m Autoslip Roam RET"

uninstall-user: ## Uninstall from user directories
	@echo "Uninstalling from user directories..."
	rm -f $(USER_LISPDIR)/$(PACKAGE)
	rm -f $(USER_LISPDIR)/$(PACKAGE:.el=.elc)
	rmdir $(USER_LISPDIR) 2>/dev/null || true
	rm -f $(USER_INFODIR)/$(INFO_FILE)
	@echo "Uninstallation complete"

# ==============================================================================
# Cleaning
# ==============================================================================

clean: ## Remove compiled files
	@echo "Cleaning..."
	rm -f *.elc
	rm -f *~
	rm -f \#*\#
	rm -rf /tmp/autoslip-test-*
	rm -rf /tmp/folgezettel-test-*

distclean: clean ## Remove all generated files
	@echo "Deep cleaning..."
	rm -f $(INFO_FILE)

# ==============================================================================
# Utilities
# ==============================================================================

list-tests: ## List all test names
	@echo "Available tests:"
	@grep -o '^(ert-deftest [a-z0-9_-]*' $(TEST_FILE) | sed 's/(ert-deftest /  /'

count-tests: ## Count total number of tests
	@echo -n "Total tests: "
	@grep -c '^(ert-deftest' $(TEST_FILE)

# ==============================================================================
# Help
# ==============================================================================

help: ## Show this help message
	@echo "Autoslip Roam Makefile"
	@echo "=============================="
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Main Targets:"
	@echo "  all              Build package and documentation (default)"
	@echo "  test             Run all tests"
	@echo "  install          Install system-wide (requires sudo)"
	@echo "  install-user     Install to user directory (no sudo)"
	@echo "  clean            Remove compiled files"
	@echo ""
	@echo "All Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  %-18s %s\n", $$1, $$2}'
	@echo ""
	@echo "Examples:"
	@echo "  make test                  # Run all 100 tests"
	@echo "  make test-unit             # Run unit tests only"
	@echo "  make info                  # Build Info documentation"
	@echo "  make install-user          # Install without sudo"
	@echo "  make test-specific TEST=test-parse-address-single-number"
	@echo "  make EMACS=/path/to/emacs test"
	@echo ""
	@echo "Documentation:"
	@echo "  After installing, access the Info manual in Emacs:"
	@echo "  C-h i d m Autoslip Roam RET"
