# Oceananigans development and AI attribution

Analysis prepared 30 September 2026 for the NEMO keynote. Seven figures are provided in PNG and vector PDF, with Julia plotting source and saved input data. This is an observational repository analysis, not a causal estimate of AI productivity.

## Findings

Matched January–August periods exclude the incomplete September 2026 observation:

| Human activity | 2024 | 2025 | 2026 | 2025–26 change |
|---|---:|---:|---:|---:|
| PRs opened | 197 | 491 | 578 | +17.7% |
| PRs merged during period | 155 | 399 | 456 | +14.3% |
| Distinct PR-opening accounts | 23 | 29 | 44 | +51.7% |
| First-time PR-opening accounts | 8 | 13 | 20 | +53.8% |

The larger activity jump was between 2024 and 2025 (+149% opened PRs), rather than immediately after ChatGPT's late-2022 launch. Availability dates are not developer adoption dates. Contributor mix, project funding, releases, changing scope, and changes in PR size could all affect these counts.

PRs opened per distinct active author decreased from 16.93 to 13.14 in 2025–26. That aggregate ratio is not a within-person productivity estimate, and is sensitive to new contributors entering partway through the period. Do not claim that every developer became faster from these data.

Across all retrieved PRs, 146 human-opened PR descriptions from 15 accounts disclose some AI assistance, including 120 Claude Code generation footers. In January–August 2026, 102 of 578 human-opened PRs (17.6%) have matched disclosures. The broader category includes assistance with tests, reasoning, preparation, or descriptions; even a generation footer does not quantify how much code was generated. The categories are reviewed keyword matches, not an exhaustive audit of every form of AI use.

The main branch retains 194 commits with Claude/Anthropic co-author trailers and 6 additional commits with Copilot trailers. All 194 Claude-tagged commits are on main's first-parent chain. No retained primary Git author name/email matches Claude, Anthropic, Codex, Copilot, or OpenAI. This establishes credited assistance, not autonomous authorship. Count each commit once regardless of repeated trailers inside a squash message. These commit and PR counts overlap and should not be added.

The approximate human open-PR inventory rose from 51 at end-2025 to 115 at end-August 2026. This is compatible with growing integration pressure, but does not establish a review bottleneck: drafts, author delays, abandoned work, CI failures, and review delays all contribute.

## Public examples worth showing

- [PR #5297: Fix nodes and immersed masking for windowed fields](https://github.com/CliMA/Oceananigans.jl/pull/5297): Benoît Pasquier explicitly acknowledges substantial Claude help; merged 14 February 2026.
- [PR #5742: Fix IsopycnalSkewSymmetricDiffusivity with ExplicitTimeDiscretization](https://github.com/CliMA/Oceananigans.jl/pull/5742): the author discloses that Claude generated code and most of the description, says he reviewed it, and requests additional review. Particularly useful for the keynote's review-capacity argument. Merged 26 August 2026.
- [PR #5937: Improve WENO's stencil computation efficiency](https://github.com/CliMA/Oceananigans.jl/pull/5937): Simone Silvestri describes using Claude to compute and verify alternative coefficients. The PR suggests fewer arithmetic operations; do not present that as a measured runtime speedup. Merged 9 September 2026.
- [PR #5962: Add ObliqueRadiation](https://github.com/CliMA/Oceananigans.jl/pull/5962): explicit acknowledgment of Claude assistance preparing a numerical boundary-condition contribution. Merged 14 September 2026.
- [Commit aa1ad5f37785](https://github.com/CliMA/Oceananigans.jl/commit/aa1ad5f37785a3020a06312a7cbfb22eae383a2e): earliest retained Claude co-author record by UTC committer date, 13 February 2026; associated with PR #5274.
- [PR #5704](https://github.com/CliMA/Oceananigans.jl/pull/5704): first observed PR by `macmccallum` includes a Claude Code footer. This is an example of a first contribution with disclosed assistance, not evidence of the person's prior programming experience.

PR #5013 was opened December 2025 but merged September 2026; its current Claude footer could have been added later. Do not interpret its creation date as proven AI adoption in December 2025.

## Figures

1. `01-development-timeline`: monthly opened/merged PRs and active/new accounts, 2019–August 2026. Thin lines are monthly values; thick lines are trailing three-month means.
2. `02-matched-period-growth`: January–August comparisons, avoiding unequal observation windows.
3. `03-ai-attribution`: present-day description disclosures grouped by PR creation month, and retained Claude co-author records grouped by UTC committer month. September is partial. Headline counts include all retrieved history.
4. `04-pr-flow`: submissions, integrations, and approximate open inventory. This is a diagnostic for the review hypothesis, not confirmation.
5. `05-commit-count-caveat`: raw non-merge vs first-parent commits. A transition toward squash-style history around early 2023 makes raw retained commit counts incomparable across workflows.

## Data and methods

- Repository: [CliMA/Oceananigans.jl](https://github.com/CliMA/Oceananigans.jl).
- Downloaded all 3,731 accessible PRs with the [GitHub list-pull-requests API](https://docs.github.com/en/rest/pulls/pulls#list-pull-requests), sorted by creation date, 100/page, until the last short page. Verified unique PR numbers. Input pagination was collected within a short window, not an atomic snapshot; PR edits may occur during collection.
- Saved 13,845 commits reachable from main at `b9725744cd313ed368bb7906880a5d884c4c78bf`. Branch-only/unmerged commits are excluded. Git history and PR API snapshots were collected minutes apart.
- PR activity excludes GitHub `Bot` accounts and logins ending `[bot]`, including the Copilot account. Human-account PRs assisted by AI remain included. Git commit activity excludes recognizable bot identities using the documented expression in `analyze.py`.
- Contributors mean distinct PR-opening GitHub accounts, not distinct people, commit authors, reviewers, or all community contributors. First-time status uses all retrieved PR history (beginning October 2018), not just the plot window. Account renames, deleted records, and multiple accounts are not reconciled.
- Merged counts use merge dates, independent of opening year. Monthly PR dates are UTC. Commit dates are committer timestamps normalized to UTC; they describe retained history and need not equal time spent coding.
- AI description search: Claude, Codex, Copilot, ChatGPT, LLM, AI-assisted/generated variants. Reviewed the matching lines; separated #5159 (logo), #5606 (agent configuration), #5880/#5949 (description only), and #6030 (performance estimate only) from the broad contribution-assistance category. #5350 remains included because it explicitly describes using Claude to analyze prior PRs while developing the contribution. Searches do not cover PR comments, reviews, or unmerged branch commit messages.
- Count a retained commit as AI-coauthored when a case-insensitive `Co-authored-by:` line contains Claude/Anthropic/Codex/Copilot/OpenAI. Distinguish this from a primary author name/email match. Attribution is self-report and optional; absence of attribution cannot classify work as human-only.
- Open inventory is reconstructed from creation and final closure timestamps. Reopening events are not fetched, so it is approximate. There are no direct reviewer-hours or quality measurements.
- Present descriptions can be edited after opening. Disclosures plotted at creation date do not date the adoption of a tool.
- Tool milestone sources: [ChatGPT, 30 November 2022](https://openai.com/index/chatgpt/); [Claude Code preview, 24 February 2025](https://www.anthropic.com/news/claude-3-7-sonnet). They are context markers, not interventions identifying causality.

## Reproduction

`data/` contains a compressed PR snapshot (only fields used by this analysis), compressed public Git metadata, derived CSVs, and snapshot metadata. Duplicate raw pagination pages and unused API fields are omitted. `ai-disclosures.csv` preserves source URLs and matched lines; `ai-commit-trailers.csv` preserves commit hashes and exact trailers. `monthly.csv` and `jan-aug-comparison.csv` contain plotted numbers.

From this directory, rebuild derived tables and figures:

```sh
python3 analyze.py
python3 combine_ai_attribution.py
julia --startup-file=no --project=. plot_history.jl
julia --startup-file=no --project=. plot_claude_share.jl
julia --startup-file=no --project=. plot_combined_share.jl
```

Python only parses/tabulates data. All figures are generated with Julia/CairoMakie, using Arial. Project.toml and Manifest.toml preserve the plotting environment.

For a stronger follow-up analysis, fetch first substantive review events, PR size/type, draft/ready transitions and reopenings; follow comparable cohorts long enough to observe merges/closures. Obtain actual adoption dates from developers and compare the same contributors over time. A simple before/after release-date comparison cannot isolate AI's effect.

## Claude share of commits (follow-up)

`06-claude-commit-share.png` / `.pdf` use **all** retained commits reachable from main, including merge and bot commits, unlike the bot-filtered activity plots. Counts use UTC committer month and the same fixed Git snapshot. Each SHA counts once.

- Entire history: 194 / 13,845 = 1.40%.
- January–August 2026: 118 / 476 = 24.79%.
- 2026 through collection on September 30: 194 / 597 = 32.50%.
- September through collection: 76 / 121 = 62.81%.

Restricting to main's first-parent chain gives 194 / 579 = 33.51% for 2026; September is unchanged. The all-history percentage is diluted by years predating these tools and by older merge workflows. These are percentages of commits carrying explicit Claude credit, not percentages of AI-written code or estimates of productivity improvement.

`data/claude-commit-share.csv` contains monthly numerator/denominator counts from `data/commits.csv`. Render with `julia --startup-file=no --project=. plot_claude_share.jl`.

## Combined Claude and Codex disclosure (follow-up)

The provider-neutral metric in figure 07 is **commits with disclosed Claude or Codex assistance**, not strictly co-author trailers. It accepts either an explicit provider co-author trailer or a reviewed assistance acknowledgment in a merged PR whose `merge_commit_sha` exactly matches a retained commit. The same rule applies to both providers. Each commit is counted once in the union, using its UTC committer date. Copilot is excluded from this two-provider metric.

The snapshot contains 14 PR descriptions acknowledging Codex; only three are merged and match retained commits: [#5529](https://github.com/CliMA/Oceananigans.jl/pull/5529), [#6078](https://github.com/CliMA/Oceananigans.jl/pull/6078), and [#6093](https://github.com/CliMA/Oceananigans.jl/pull/6093). No Codex trailers were found. Unmerged PRs cannot increase a main-history commit numerator.

Applying the broader rule also identifies seven additional Claude-associated commits from PR descriptions, yielding 201 Claude-associated commits and 3 Codex-associated commits, with no overlap. Total: **204 / 597 = 34.17%** in 2026 through the snapshot. September: **80 / 121 = 66.12%** (78 Claude, 2 Codex). January–August: **124 / 476 = 26.05%**. These are lower-bound observed disclosures, not exhaustive assistance detection or comparative provider market shares.

PR #5376 has a Claude footer and is marked merged, but its merge SHA is absent from saved main history. It is excluded rather than assigned speculatively. `data/unmatched-ai-prs.json` records this case. Non-squash PRs are linked only to the exact merge SHA, not every branch commit, so the method is conservative and workflow-sensitive. Current PR descriptions can postdate the associated commit.

Reproduce with `python3 combine_ai_attribution.py` then `julia --startup-file=no --project=. plot_combined_share.jl`. The per-commit evidence table is `data/combined-ai-commit-evidence.csv`; monthly numerators and denominators are in `data/combined-ai-commit-share.csv`.

## Frozen inputs and refreshes

`pull_requests.json.gz` preserves the PR fields read by the scripts, including the original description text. `commits.raw.gz` preserves public Git metadata. `first-parent.txt` records the first-parent chain. `SHA256SUMS` checks those inputs. The snapshot metadata PR count was corrected from an obsolete 3,600 to the verified 3,731 records; the calculations already used all 3,731.

To collect a separate, current PR snapshot:

```sh
python3 fetch_prs.py --output /path/to/new-snapshot
```

The output directory must not exist. An optional `GITHUB_TOKEN` environment variable increases GitHub API rate limits. No token is written to the output. Updating the frozen analysis requires a matching Git snapshot, revised time windows and labels, and another manual review of disclosure matches; this command alone does not update the keynote’s analysis.

The saved Git metadata can also be reconstructed from the public repository:

```sh
git clone --bare https://github.com/CliMA/Oceananigans.jl.git oceananigans-history.git
git --git-dir=oceananigans-history.git log b9725744cd313ed368bb7906880a5d884c4c78bf --format='%x1e%H%x1f%aI%x1f%cI%x1f%an%x1f%ae%x1f%cn%x1f%ce%x1f%P%x1f%B' > commits.raw
git --git-dir=oceananigans-history.git rev-list --first-parent b9725744cd313ed368bb7906880a5d884c4c78bf > first-parent.txt
```

PR bodies cannot be recovered as-of the collection time from a current API response; use the included frozen snapshot to reproduce the original disclosure counts.
