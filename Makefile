.PHONY: test check
test:
	bash tests/run.sh
	python3 tests/spinner.py
	@if [ "$$(uname -s)" = Darwin ]; then bash tests/macos.sh; fi
check: test
	@if command -v shellcheck >/dev/null; then shellcheck bin/ai-shell integrations/bash-integration.bash install.sh install-macos.sh install-online.sh uninstall.sh scripts/prompt-key.bash scripts/build-online-installer.sh tests/run.sh tests/macos.sh tests/live.sh tests/helpers/fake-curl; else echo 'shellcheck unavailable'; fi
