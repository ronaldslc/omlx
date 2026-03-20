FORMULA := Formula/omlx.rb
GITHUB_REPO := ronaldslc/omlx
OMLX_PIP := /opt/homebrew/opt/omlx/libexec/bin/pip

.PHONY: update-formula install-torch

update-formula: ## Update git commit SHA and sha256 in omlx.rb (bump version in formula first!)
	@echo ""
	@echo "⚠️  Did you bump the version in $(FORMULA) before running this? (e.g. 0.2.23-fix → 0.2.24-fix)"
	@echo "   Press Enter to continue, or Ctrl-C to abort and update the version first."
	@read _confirm
	@COMMIT=$$(git rev-parse --short=7 HEAD); \
	URL="https://github.com/$(GITHUB_REPO)/archive/$$COMMIT.tar.gz"; \
	echo "→ Fetching $$URL to compute sha256..."; \
	SHA=$$(curl -sL "$$URL" | shasum -a 256 | awk '{print $$1}'); \
	echo "→ Commit: $$COMMIT"; \
	echo "→ sha256: $$SHA"; \
	sed -i '' "s|url \"https://github.com/$(GITHUB_REPO)/archive/[^\"]*\"|url \"$$URL\"|" $(FORMULA); \
	sed -i '' "s|sha256 \"[^\"]*\"|sha256 \"$$SHA\"|" $(FORMULA); \
	echo "✅ $(FORMULA) updated."; \
	echo ""; \
	echo "Next steps:"; \
	echo "  1. Review the changes:        git diff $(FORMULA)"; \
	echo "  2. Copy formula to tap:       cp $(FORMULA) /opt/homebrew/Library/Taps/ronaldslc/homebrew-omlx/Formula/omlx.rb"; \
	echo "  3. Reinstall local omlx:      brew reinstall omlx"; \
	echo ""

install-torch: ## Install torch + torchvision into the omlx Homebrew venv
	@echo "→ Installing torch and torchvision (no-deps to avoid setuptools conflict)..."
	$(OMLX_PIP) install --no-deps torch torchvision
	@echo "→ Installing torch runtime dependencies..."
	$(OMLX_PIP) install sympy networkx mpmath
	@echo "✅ torch and torchvision installed into omlx venv."

# Patch targets for qwen3_coder tool parser (ast.literal_eval SyntaxError fix)
# Supports oMLX.app and Homebrew installs; auto-detects which is present.
QWEN3_CODER_APP := /Applications/oMLX.app/Contents/Python/framework-mlx-framework/lib/python3.11/site-packages/mlx_lm/tool_parsers/qwen3_coder.py
QWEN3_CODER_BREW := $(shell ls /opt/homebrew/Cellar/omlx/*/libexec/lib/python*/site-packages/mlx_lm/tool_parsers/qwen3_coder.py 2>/dev/null | head -1)

.PHONY: patch-qwen3-coder unpatch-qwen3-coder

# Internal helper — patches a single file.  Usage: $(call _patch_one,/path/to/qwen3_coder.py)
define _patch_one
	@target="$(1)"; \
	if [ ! -f "$$target" ]; then exit 0; fi; \
	if grep -q 'except (SyntaxError, ValueError):' "$$target"; then \
		echo "Already patched: $$target"; exit 0; \
	fi; \
	cp "$$target" "$$target.bak"; \
	python3 -c "\
	import pathlib, sys; \
	p = pathlib.Path(sys.argv[1]); \
	src = p.read_text(); \
	src = src.replace( \
	    'except json.JSONDecodeError:\n                return ast.literal_eval(param_value)', \
	    'except json.JSONDecodeError:\n                try:\n                    return ast.literal_eval(param_value)\n                except (SyntaxError, ValueError):\n                    return param_value'); \
	src = src.replace( \
	    '        return ast.literal_eval(param_value)\n\n\ndef _parse_xml_function_call', \
	    '        try:\n            return ast.literal_eval(param_value)\n        except (SyntaxError, ValueError):\n            return param_value\n\n\ndef _parse_xml_function_call'); \
	p.write_text(src); \
	" "$$target"; \
	echo "Patched $$target"; \
	echo "Backup saved to $$target.bak"
endef

patch-qwen3-coder: ## Fix ast.literal_eval SyntaxError crash in qwen3_coder tool parser
	@found=0; \
	for f in "$(QWEN3_CODER_APP)" "$(QWEN3_CODER_BREW)"; do \
		[ -f "$$f" ] && found=1; \
	done; \
	if [ $$found -eq 0 ]; then \
		echo "ERROR: qwen3_coder.py not found. Is oMLX.app or Homebrew omlx installed?"; exit 1; \
	fi
	$(call _patch_one,$(QWEN3_CODER_APP))
	$(call _patch_one,$(QWEN3_CODER_BREW))

unpatch-qwen3-coder: ## Restore original qwen3_coder tool parser
	@restored=0; \
	for f in "$(QWEN3_CODER_APP)" "$(QWEN3_CODER_BREW)"; do \
		if [ -f "$$f.bak" ]; then \
			mv "$$f.bak" "$$f"; \
			echo "Restored $$f"; \
			restored=1; \
		fi; \
	done; \
	if [ $$restored -eq 0 ]; then \
		echo "ERROR: No backups found."; exit 1; \
	fi
