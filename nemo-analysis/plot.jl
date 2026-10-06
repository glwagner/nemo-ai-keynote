using CairoMakie, JSON, Statistics
const ROOT=@__DIR__;const D=joinpath(ROOT,"data")
const teal="#167D8D";const orange="#C57335";const ink="#173541";const gray="#ABBEC3"
set_theme!(Theme(font="Arial",fontsize=20,textcolor=ink,figure_padding=32,Axis=(titlealign=:left,titlesize=23,xgridvisible=false,ygridcolor=(:gray,0.15),topspinevisible=false,rightspinevisible=false)))
function table(f)
 ls=readlines(joinpath(D,f));ks=split(first(ls),',');[Dict(zip(ks,split(l,','))) for l in ls[2:end]]
end
vals(rs,k)=parse.(Float64,getindex.(rs,k))
function savefig(f,n)
 save(joinpath(ROOT,n*".png"),f,px_per_unit=1.5);save(joinpath(ROOT,n*".pdf"),f)
end
m=filter(r->r["month"]<="2026-09",table("monthly.csv"));s=JSON.parsefile(joinpath(D,"summary.json"))
f=Figure(size=(1450,970))
Label(f[0,1:2],"NEMO development in the public GitLab record",fontsize=33,font=:bold,halign=:left)
Label(f[1,1:2],"January 2022–September 2026 • complete months • all target branches",fontsize=20,halign=:left,color=teal)
for (pos,k,t,c) in [((2,1),"mrs_opened","Merge requests opened",teal),((2,2),"mrs_merged","Merge requests merged",teal),((3,1),"authors","Distinct MR-opening accounts",orange),((3,2),"first_time_authors","First observed MR-opening accounts",orange)]
 ax=Axis(f[pos...],title=t,ylabel="Count / month",xticks=([1,13,25,37,49],["2022","2023","2024","2025","2026"]))
 v=vals(m,k);lines!(ax,1:length(v),v,color=(c,0.4),linewidth=1.5);lines!(ax,1:length(v),[mean(v[max(1,i-2):i]) for i in eachindex(v)],color=c,linewidth=3)
 ylims!(ax,0,maximum(v)*1.15);xlims!(ax,0,length(m)+1)
end
Label(f[4,1:2],"Source: forge.nemo-ocean.eu/nemo/nemo; 1,214 public MRs, collected 6 Oct 2026. Thin: monthly; thick: trailing 3-month mean.\nThe GitLab record starts in November 2021; first observed contributors may have contributed earlier. Accounts are not necessarily people.\nIncludes release-branch backports, which can count the same work more than once. Activity does not identify an AI productivity effect.",fontsize=15,color="#58717A",halign=:left,justification=:left)
savefig(f,"01-nemo-development-timeline")
f=Figure(size=(1420,870))
Label(f[0,1:2],"NEMO: fewer merge requests, more participating accounts in 2026",fontsize=29,font=:bold,halign=:left)
Label(f[1,1:2],"January–August comparisons • all target branches",fontsize=21,halign=:left,color=teal)
a=table("jan-aug-comparison.csv");years=Int.(vals(a,"year"))
for(pos,k,t,c)in [((2,1),"mrs_opened","MRs opened: 172 → 155 (−10%)",teal),((2,2),"mrs_merged","MRs merged: 149 → 125 (−16%)",teal),((3,1),"authors","Distinct accounts: 17 → 20 (+18%)",orange),((3,2),"first_time_authors","First observed accounts: 3 → 5",orange)]
 ax=Axis(f[pos...],title=t,xticks=(years,string.(years)),ylabel="Jan–Aug count");v=vals(a,k)
 barplot!(ax,years,v,color=[y>=2025 ? c : gray for y in years],bar_labels=string.(Int.(v)),label_size=18);ylims!(ax,0,maximum(v)*1.22)
end
Label(f[4,1:2],"Source: public NEMO GitLab MRs, snapshot 6 Oct 2026. Headline changes compare 2025 with 2026. No known bot-pattern accounts found.\nMain-target MRs alone: opened 89 → 94; merged 75 → 70. Branch/backport practices affect the all-target totals.\nThese are activity measures, not evidence for or against AI use, hours saved, or scientific quality.",fontsize=15,color="#58717A",halign=:left,justification=:left)
savefig(f,"02-nemo-matched-periods")
f=Figure(size=(1400,810))
Label(f[0,1],"Recorded Claude/Codex assistance—not total AI use",fontsize=34,font=:bold,halign=:left)
Label(f[1,1],"January–August 2026 • explicit co-author credit or linked MR/PR description disclosure",fontsize=20,color=teal,halign=:left)
oa=readlines(joinpath(ROOT,"../analysis/data/combined-ai-commit-share.csv"));rs=[split(l,',') for l in oa[2:end] if first(split(l,','))<"2026-09"]
num=sum(parse(Int,r[5]) for r in rs);den=sum(parse(Int,r[6]) for r in rs);nn=s["main_jan_aug_2026_commits"]
ax=Axis(f[2,1],ylabel="Main-reachable commits with disclosure (%)",xticks=([1,2],["Oceananigans","NEMO"]),yticks=0:10:50)
barplot!(ax,[1,2],[100num/den,0],color=[teal,gray]);ylims!(ax,0,50);xlims!(ax,0.4,2.6)
text!(ax,1,100num/den+1,text="$(num)/$(den) = $(round(100num/den,digits=1))%",align=(:center,:bottom),fontsize=23)
text!(ax,2,1,text="0/$(nn) observed\nActual use is unknown",align=(:center,:bottom),fontsize=23)
Label(f[3,1],"NEMO search: no AI-tool markers in 1,214 MR titles/descriptions or 2,258 commits across main + two release branches.",fontsize=19,font=:bold,halign=:left)
Label(f[4,1],"Sources: Oceananigans snapshot 30 Sep 2026; NEMO snapshot 6 Oct 2026. Each SHA counted once; bots and merges included.\nPR/MR descriptions can change after merge. Disclosure conventions and merge workflows differ between projects.\nNEMO discussion APIs require authentication; comments, private forks, and unmerged branch commits were not assessed.\nZero observed disclosure does not establish zero AI use. This is not a comparison of productivity or adoption rates.",fontsize=15,color="#58717A",halign=:left,justification=:left)
savefig(f,"03-nemo-ai-disclosure")
println("Saved three NEMO PNG/PDF figures.")
