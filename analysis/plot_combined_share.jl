using CairoMakie
root=@__DIR__
r=[split(l,',') for l in readlines(joinpath(root,"data/combined-ai-commit-share.csv"))[2:end]]
cl=parse.(Int,getindex.(r,2));co=parse.(Int,getindex.(r,3));both=parse.(Int,getindex.(r,4));a=parse.(Int,getindex.(r,5));n=parse.(Int,getindex.(r,6));pct=100 .* a ./ n
set_theme!(Theme(font="Arial",fontsize=22,textcolor="#1B2A33",figure_padding=35))
f=Figure(size=(1360,800))
Label(f[0,1],"Disclosed Claude or Codex assistance: 66% of September commits",fontsize=30,font=:bold,halign=:left)
Label(f[1,1],"2026 to date: $(sum(a)) / $(sum(n)) commits ($(round(100sum(a)/sum(n),digits=1))%)",fontsize=23,color="#2A7F8E",halign=:left)
ax=Axis(f[2,1],ylabel="Commits with disclosed assistance (%)",xticks=(1:9,["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep*"]),yticks=0:20:100,xgridvisible=false,ygridcolor=(:gray,0.15),topspinevisible=false,rightspinevisible=false)
barplot!(ax,1:9,pct,color="#D27A36",label="Codex (PR disclosure)")
barplot!(ax,1:9,100 .* (cl .+ both) ./ n,color="#2A7F8E",label="Claude (trailer or PR disclosure)")
for i in 1:9
 text!(ax,i,pct[i]+1,text="$(round(pct[i],digits=1))%\n$(a[i])/$(n[i])",align=(:center,:bottom),fontsize=19)
end
ylims!(ax,0,100);axislegend(ax,position=:lt,labelsize=17)
Label(f[3,1],"Source: CliMA/Oceananigans.jl, main at b9725744cd31; 30 Sep 2026. *September is partial through collection.\nEvidence: explicit co-author trailer OR assistance disclosure in a merged PR whose merge SHA matches the commit.\nDenominator: all retained main-reachable commits, including bots and merges; UTC committer month. Count each SHA once.\nOptional disclosures are incomplete and do not quantify AI-written code. PR descriptions may have been edited after merge.",fontsize=15,color="#5B6B75",halign=:left,justification=:left)
save(joinpath(root,"07-combined-ai-commit-share.png"),f,px_per_unit=1.5)
save(joinpath(root,"07-combined-ai-commit-share.pdf"),f)
