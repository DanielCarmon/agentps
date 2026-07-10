# procview — Makefile.  Vibecoded by Daniel Carmon and Claude Opus 4.8.  GNU GPL v3.0-or-later.
PREFIX ?= $(HOME)/.local

.PHONY: install uninstall help

help:
	@echo "make install    - install the procview CLI + Claude Code capture hook"
	@echo "make uninstall  - remove them and deregister the hook"
	@echo "                  (override install dir with: make install PREFIX=/usr/local)"

install:
	@PREFIX="$(PREFIX)" ./install.sh install

uninstall:
	@PREFIX="$(PREFIX)" ./install.sh uninstall
