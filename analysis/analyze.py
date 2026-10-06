"""Download is separate; no plotting. Rebuilds auditable tables from saved Git/API data."""
import json,re,csv,collections,datetime,statistics,pathlib,subprocess,gzip
ROOT=pathlib.Path(__file__).resolve().parent
D=ROOT/'data'; prs=json.loads(gzip.decompress((D/'pull_requests.json.gz').read_bytes()))
assert len(prs)==len({p['number'] for p in prs})
raw=gzip.decompress((D/'commits.raw.gz').read_bytes()).decode(); fp=set((D/'first-parent.txt').read_text().split())
commits=[]
for block in raw.split('\x1e'):
 v=block.strip().split('\x1f',8)
 if len(v)!=9:continue
 sha,ad,cd,name,email,cn,ce,parents,msg=v
 cd=datetime.datetime.fromisoformat(cd).astimezone(datetime.timezone.utc).isoformat()
 trailers=re.findall(r'(?im)^Co-authored-by:.*(?:claude|anthropic|codex|copilot|openai).*$',msg)
 bot=bool(re.search(r'\[bot\]|github.actions|dependabot|noreply@juliacomputing|JuliaTagBot|CompatHelper',name+' '+email,re.I))
 commits.append(dict(sha=sha,date=cd[:10],author_date=ad[:10],author=name,email=email,subject=msg.splitlines()[0],first_parent=sha in fp,merge=len(parents.split())>1,bot=bot,ai_coauthor=bool(trailers),ai_trailers=' | '.join(trailers),claude_coauthor=any(re.search('claude|anthropic',t,re.I) for t in trailers),ai_author=bool(re.search(r'claude|anthropic|codex|copilot|openai',name+' '+email,re.I))))
def writecsv(name,rows):
 with open(D/name,'w') as f:
  w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
def isbot(p):return p['user']['type']=='Bot' or p['user']['login'].endswith('[bot]')
pat=re.compile(r'claude|codex|copilot|chatgpt|\bLLM\b|AI.assist|AI.generat',re.I)
# Manually checked all matching description lines. These mention tools without disclosing code generation.
other={5606:'agent configuration only',5880:'description-only disclosure',5949:'description-only disclosure',5159:'logo generation',6030:'performance estimate only'}
rows=[]
for p in prs:
 body=p['body'] or ''; matches=[l for l in body.splitlines() if pat.search(l)]
 category=other.get(p['number'],'disclosed assistance' if matches else 'no matched disclosure')
 rows.append(dict(number=p['number'],url=p['html_url'],title=p['title'],author=p['user']['login'],bot=isbot(p),created=p['created_at'],merged=p['merged_at'] or '',closed=p['closed_at'] or '',state=p['state'],category=category,claude_footer=bool(re.search(r'Generated with.*Claude Code',body,re.I)),ai_disclosed=category=='disclosed assistance',matched_lines=' | '.join(matches)))
writecsv('pull-request-metadata.csv',rows);writecsv('commits.csv',commits)
writecsv('ai-disclosures.csv',[r for r in rows if r['category']!='no matched disclosure']);writecsv('ai-commit-trailers.csv',[c for c in commits if c['ai_coauthor']])
human=[r for r in rows if not r['bot']]
first={}
for p in sorted(human,key=lambda x:x['created']):first.setdefault(p['author'],p['created'][:7])
months=[f'{y}-{m:02d}' for y in range(2019,2027) for m in range(1,13) if (y,m)<=(2026,9)]
metrics=[]
for month in months:
 opened=[p for p in human if p['created'].startswith(month)]
 merged=[p for p in human if p['merged'].startswith(month)]
 cs=[c for c in commits if c['date'].startswith(month) and not c['bot']]
 # Month-end open count inferred from final close timestamps; reopened histories are unavailable.
 y,m=map(int,month.split('-'));end=f'{y+(m==12)}-{m%12+1:02d}-01'
 latency=[(datetime.datetime.fromisoformat(p['merged'].replace('Z','+00:00'))-datetime.datetime.fromisoformat(p['created'].replace('Z','+00:00'))).total_seconds()/86400 for p in merged]
 metrics.append(dict(month=month,prs_opened=len(opened),prs_merged=len(merged),authors=len({p['author'] for p in opened}),first_time_authors=sum(v==month for v in first.values()),nonmerge_commits=sum(not c['merge'] for c in cs),first_parent_commits=sum(c['first_parent'] for c in cs),ai_disclosed_prs=sum(p['ai_disclosed'] for p in opened),claude_footer_prs=sum(p['claude_footer'] for p in opened),ai_coauthor_commits=sum(c['ai_coauthor'] for c in cs),claude_coauthor_commits=sum(c['claude_coauthor'] for c in cs),median_merge_days=statistics.median(latency) if latency else 0,open_at_month_end=sum(p['created'][:10]<end and (not p['closed'] or p['closed'][:10]>=end) for p in human)))
writecsv('monthly.csv',metrics)
annual=[]
for y in range(2019,2027):
 subset=[m for m in metrics if m['month'].startswith(str(y)) and int(m['month'][5:])<=8]
 pr=[p for p in human if p['created'].startswith(str(y)) and int(p['created'][5:7])<=8]
 a=dict(year=y,prs_opened=sum(m['prs_opened'] for m in subset),prs_merged=sum(m['prs_merged'] for m in subset),distinct_pr_authors=len({p['author'] for p in pr}),first_time_pr_authors=sum(m['first_time_authors'] for m in subset),first_parent_commits=sum(m['first_parent_commits'] for m in subset),nonmerge_commits=sum(m['nonmerge_commits'] for m in subset),ai_disclosed_prs=sum(m['ai_disclosed_prs'] for m in subset))
 annual.append(a)
writecsv('jan-aug-comparison.csv',annual)
# Rebuild the input to figure 06 using all retained commits, including bots/merges.
claude_share=[]
for month in sorted({c['date'][:7] for c in commits if c['date'] >= '2026-01-01'}):
 cs=[c for c in commits if c['date'].startswith(month)]
 n=sum(c['claude_coauthor'] for c in cs)
 claude_share.append(dict(month=month,claude=n,total=len(cs),percent=100*n/len(cs)))
writecsv('claude-commit-share.csv',claude_share)
summary=dict(pr_count=len(prs),commits=len(commits),ai_trailers=sum(c['ai_coauthor'] for c in commits),claude_trailers=sum(c['claude_coauthor'] for c in commits),ai_primary_author_commits=sum(c['ai_author'] for c in commits),human_pr_disclosures=sum(p['ai_disclosed'] for p in human),disclosing_human_authors=len({p['author'] for p in human if p['ai_disclosed']}),claude_footers=sum(p['claude_footer'] for p in human),annual=annual,recent=metrics[-13:])
(D/'summary.json').write_text(json.dumps(summary,indent=2));print(json.dumps(summary,indent=2))
