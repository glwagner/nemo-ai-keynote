using CairoMakie, JSON, Statistics
const ROOT = @__DIR__
const D = joinpath(ROOT, "data")
const teal = "#2A7F8E"
const ink = "#1B2A33"
const orange = "#D27A36"
const gray = "#BFC9CE"
set_theme!(Theme(font="Arial", fontsize=19, textcolor=ink, Axis=(titlealign=:left, titlesize=23, xlabelsize=18, ylabelsize=18, xgridvisible=false, ygridcolor=(:gray,0.15), topspinevisible=false, rightspinevisible=false), figure_padding=30))
s = JSON.parsefile(joinpath(D,"summary.json"))
function table(file)
    ls=readlines(joinpath(D,file)); keys=split(ls[1],',')
    [Dict(k=>v for (k,v) in zip(keys,split(l,','))) for l in ls[2:end]]
end
m=table("monthly.csv"); complete=m[1:end-1]
v(rows,key)=parse.(Float64,getindex.(rows,key))
function finish(f,name)
    save(joinpath(ROOT,name*".png"), f, px_per_unit=1.5)
    save(joinpath(ROOT,name*".pdf"), f)
end
function footer(f,row,msg)
    Label(f[row,1:2],msg,fontsize=14,color="#5B6B75",halign=:left,justification=:left)
end
function timeline!(ax;n=length(complete))
    ax.xticks=([1,13,25,37,49,61,73,85],["2019","2020","2021","2022","2023","2024","2025","2026"])
    xlims!(ax,0,n+1)
    vlines!(ax,[47.97],color=(orange,0.7),linestyle=:dash,linewidth=1.5)
    vlines!(ax,[74.8],color=(teal,0.7),linestyle=:dash,linewidth=1.5)
end
f=Figure(size=(1440,960))
Label(f[0,1:2],"Oceananigans development: growth, with a broader contributor base",fontsize=31,font=:bold,halign=:left)
Label(f[1,1:2],"Monthly human PR activity through August 2026  •  Dashed lines mark ChatGPT (Nov 2022) and Claude Code preview (Feb 2025)",fontsize=17,halign=:left)
for (pos,key,title,col) in [((2,1),"prs_opened","PRs opened",teal),((2,2),"prs_merged","PRs merged",teal),((3,1),"authors","Distinct PR authors each month",orange),((3,2),"first_time_authors","First-time PR authors each month",orange)]
    ax=Axis(f[pos...],title=title,ylabel="Count / month")
    vals=v(complete,key); lines!(ax,1:length(vals),vals,color=(col,0.4),linewidth=1.5)
    sm=[mean(vals[max(1,i-2):i]) for i in eachindex(vals)]
    lines!(ax,1:length(vals),sm,color=col,linewidth=3,label="Trailing 3-month mean")
    timeline!(ax); ylims!(ax,0,maximum(vals)*1.15)
end
footer(f,4,"Source: CliMA/Oceananigans.jl GitHub PR metadata, retrieved 30 Sep 2026. Bots excluded; authors = GitHub accounts.\nThin lines: monthly counts; thick lines: trailing 3-month mean. Milestones mark tool availability, not causation.\nFirst-time authors = first observed PR; not necessarily novice developers.")
finish(f,"01-development-timeline")

f=Figure(size=(1440,820))
Label(f[0,1:2],"More contributors; a smaller increase in merged output",fontsize=33,font=:bold,halign=:left)
Label(f[1,1:2],"January–August in each year  •  Human-opened PRs only",fontsize=20,halign=:left)
a=s["annual"]
for (pos,key,title,col) in [((2,1),"prs_opened","PRs opened: 491 → 578  (+18%)",teal),((2,2),"prs_merged","PRs merged: 399 → 456  (+14%)",teal),((3,1),"distinct_pr_authors","Distinct PR authors: 29 → 44  (+52%)",orange),((3,2),"first_time_pr_authors","First-time PR authors: 13 → 20  (+54%)",orange)]
    vals=Float64[x[key] for x in a]; years=Int[x["year"] for x in a]
    ax=Axis(f[pos...],title=title,xticks=(years,string.(years)),ylabel="Jan–Aug count")
    barplot!(ax,years,vals,color=[y>=2025 ? col : gray for y in years],bar_labels=string.(Int.(vals)),label_size=17)
    ylims!(ax,0,maximum(vals)*1.22)
end
footer(f,4,"Source: CliMA/Oceananigans.jl GitHub PR metadata, 30 Sep 2026. Bots excluded. Headline changes compare 2025 with 2026.\nThese are activity measures, not hours saved, scientific quality, or a causal estimate of AI's effect.")
finish(f,"02-matched-period-growth")

f=Figure(size=(1440,850))
Label(f[0,1:2],"AI assistance leaves a measurable public footprint",fontsize=34,font=:bold,halign=:left)
Label(f[1,1:2],"146 human-opened PRs disclose assistance  •  15 authors  •  194 retained commits credit Claude as co-author",fontsize=22,halign=:left,color=teal)
recent=m[end-8:end]; xs=collect(1:9); labels=["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep*"]
ax=Axis(f[2,1],title="PR descriptions disclosing AI assistance",xticks=(xs,labels),ylabel="PRs opened in 2026")
total=v(recent,"prs_opened"); ai=v(recent,"ai_disclosed_prs")
barplot!(ax,xs,total,color=gray,label="No matched disclosure")
barplot!(ax,xs,ai,color=teal,label="Disclosed assistance")
axislegend(ax,position=:lt,labelsize=16)
ax2=Axis(f[2,2],title="Claude co-author trailers in retained commits",xticks=(xs,labels),ylabel="Commits, by UTC committer month")
cc=v(recent,"claude_coauthor_commits")
barplot!(ax2,xs,cc,color=teal,bar_labels=string.(Int.(cc)),label_size=18)
ylims!(ax2,0,maximum(cc)*1.2)
Label(f[3,1:2],"Co-author credit ≠ autonomous authorship. No retained commit names Claude as its primary Git author.",fontsize=21,font=:bold,halign=:left)
footer(f,4,"Source: PR descriptions + main-branch Git history, 30 Sep 2026. *September is partial through collection time.\nDisclosures include footers and explicit acknowledgments; they do not identify how much code was AI-written. PR text can be edited later.\nMissing disclosure does not mean no AI use. Description-only / logo-only / tool-configuration mentions excluded; bots excluded from PR panel.")
finish(f,"03-ai-attribution")

f=Figure(size=(1440,850))
Label(f[0,1:2],"Incoming PRs and open inventory both increased",fontsize=31,font=:bold,halign=:left)
Label(f[1,1:2],"Human PRs, January 2024–August 2026",fontsize=20,halign=:left)
r=filter(x->x["month"]>="2024-01",complete);xs=1:length(r)
ax=Axis(f[2,1],title="PRs opened and merged",ylabel="PRs / month",xticks=([1,7,13,19,25,31],["Jan 24","Jul 24","Jan 25","Jul 25","Jan 26","Jul 26"]))
lines!(ax,xs,v(r,"prs_opened"),color=orange,linewidth=3,label="Opened")
lines!(ax,xs,v(r,"prs_merged"),color=teal,linewidth=3,label="Merged")
axislegend(ax,position=:lt,labelsize=17)
ax2=Axis(f[2,2],title="Approximate open PR inventory",ylabel="Open PRs at month end",xticks=([1,7,13,19,25,31],["Jan 24","Jul 24","Jan 25","Jul 25","Jan 26","Jul 26"]))
lines!(ax2,xs,v(r,"open_at_month_end"),color=ink,linewidth=3)
ylims!(ax,0,140); ylims!(ax2,0,125)
Label(f[3,1:2],"Open inventory: 51 at end-2025 → 115 at end-August 2026",fontsize=27,color=teal,font=:bold,halign=:left)
footer(f,4,"Source: CliMA/Oceananigans.jl PR metadata, 30 Sep 2026. Inventory uses creation / final closure dates; excludes reopening history.\nOpen PRs may be drafts, waiting on authors, blocked by tests, or awaiting review. Inventory does not measure reviewer workload.\nA review-bottleneck claim needs review events, PR size/type, contributor mix, and adoption dates.")
finish(f,"04-pr-flow")

f=Figure(size=(1440,800))
Label(f[0,1:2],"Raw commit counts change when the merge workflow changes",fontsize=33,font=:bold,halign=:left)
Label(f[1,1:2],"Oceananigans main-branch history, January 2019–August 2026",fontsize=20,halign=:left)
ax=Axis(f[2,1:2],ylabel="Commits / month")
lines!(ax,1:length(complete),v(complete,"nonmerge_commits"),color=orange,linewidth=2,label="All retained non-merge commits")
lines!(ax,1:length(complete),v(complete,"first_parent_commits"),color=teal,linewidth=3,label="First-parent main history")
timeline!(ax);axislegend(ax,position=:rt)
footer(f,3,"Source: main history at b9725744cd31, 30 Sep 2026. Known bot identities excluded; dates use committer time in UTC.\nFirst-parent history follows main's integration path. Squashing removes intermediate branch commits from retained main history.\nDashed lines: ChatGPT (Nov 2022), Claude Code preview (Feb 2025). Raw commit totals are not a consistent productivity measure.")
finish(f,"05-commit-count-caveat")
println("Saved five PNG and PDF figures.")
