PYTHON ?= python3
JULIA ?= julia

.PHONY: reproduce tables figures setup verify-data

reproduce: verify-data tables figures

setup:
	$(JULIA) --startup-file=no --project=analysis -e 'using Pkg; Pkg.instantiate()'

verify-data:
	cd analysis/data && shasum -a 256 -c SHA256SUMS

tables:
	$(PYTHON) analysis/analyze.py
	$(PYTHON) analysis/combine_ai_attribution.py

figures: tables
	$(JULIA) --startup-file=no --project=analysis analysis/plot_history.jl
	$(JULIA) --startup-file=no --project=analysis analysis/plot_claude_share.jl
	$(JULIA) --startup-file=no --project=analysis analysis/plot_combined_share.jl
