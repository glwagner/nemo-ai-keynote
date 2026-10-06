using CairoMakie
root=@__DIR__
rows=[split(l,',') for l in readlines(joinpath(root,"data/claude-commit-share.csv"))[2:end]]
a=parse.(Int,getindex.(rows,2)); n=parse.(Int,getindex.(rows,3)); pct=parse.(Float64,getindex.(rows,4))
set_theme!(Theme(font="Arial",fontsize=22,textcolor="#1B2A33",figure_padding=35))
f=Figure(size=(1300,760))
Label(f[0,1],"Claude co-author credit reached 63% of September commits",fontsize=31,font=:bold,halign=:left)
Label(f[1,1],"Oceananigans main-branch history • 2026 to date: 194 / 597 commits (32.5%)",fontsize=23,color="#2A7F8E",halign=:left)
labels=["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep*"]
ax=Axis(f[2,1],ylabel="Commits crediting Claude (%)",xticks=(1:9,labels),yticks=0:20:100,xgridvisible=false,ygridcolor=(:gray,0.15),topspinevisible=false,rightspinevisible=false)
barplot!(ax,1:9,pct,color=[i==9 ? "#D27A36" : "#2A7F8E" for i in 1:9],bar_labels=["$(round(p,digits=1))%\n$(ai)/$(ni)" for (p,ai,ni) in zip(pct,a,n)],label_size=19)
ylims!(ax,0,100)
Label(f[3,1],"Source: CliMA/Oceananigans.jl, main at b9725744cd31; snapshot 30 Sep 2026. *September is partial through collection.\nDenominator: all retained commits reachable from main, including merge and bot commits; UTC committer month.\nEach commit counted once. Co-author trailers disclose assistance, not the fraction of code AI wrote; attribution is optional.",fontsize=15,color="#5B6B75",halign=:left,justification=:left)
save(joinpath(root,"06-claude-commit-share.png"),f,px_per_unit=1.5)
save(joinpath(root,"06-claude-commit-share.pdf"),f)
