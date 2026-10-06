"""Analyze a frozen public NEMO snapshot. Tabulation only; plots are Julia."""
import collections,csv,datetime,gzip,hashlib,json,pathlib,re,statistics
D=pathlib.Path(__file__).resolve().parent/'data'
pattern=re.compile(r'\bclaude\b|\bcodex\b|anthropic|openai|copilot|chatgpt|\bLLMs?\b|AI.assist|AI.generat|\bAI\b|\bGPT(?:[- ]?\d|\b)|\bGemini\b|language model|artificial intelligence',re.I)
providers={'claude':re.compile(r'\bclaude\b|anthropic',re.I),'codex':re.compile(r'\bcodex\b',re.I)}
def load(f):return json.loads(gzip.decompress((D/f).read_bytes()))
def write(name,rows,fields):
 with (D/name).open('w',newline='') as f:
  w=csv.DictWriter(f,fieldnames=fields,lineterminator='\n');w.writeheader();w.writerows(rows)
def utc(s):return datetime.datetime.fromisoformat(s.replace('Z','+00:00')).astimezone(datetime.timezone.utc).isoformat()
def textmatches(txt):return '\n'.join(line for line in txt.splitlines() if pattern.search(line))
snapshot=json.loads((D/'snapshot.json').read_text());mrs=load('merge_requests.json.gz');assert len(mrs)==len({r['iid'] for r in mrs})
main=set((D/'main-commits.txt').read_text().split());fp=set((D/'first-parent.txt').read_text().split());commits=[];matches=[]
for b in gzip.decompress((D/'all-branches-commits.raw.gz').read_bytes()).decode().split('\x1e'):
 v=b.strip().split('\x1f',8)
 if len(v)!=9:continue
 sha,ad,cd,name,email,cn,ce,parents,msg=v
 trailers='\n'.join(re.findall(r'(?im)^Co-authored-by:.*$',msg))
 cs=dict(sha=sha,date=utc(cd)[:10],author=name,subject=msg.splitlines()[0],main=sha in main,first_parent=sha in fp,merge=len(parents.split())>1,bot=bool(re.search(r'\[bot\]|dependabot|github.actions|gitlab.bot',name+' '+email,re.I)),claude_coauthor=bool(providers['claude'].search(trailers)),codex_coauthor=bool(providers['codex'].search(trailers)),ai_primary_author=bool(pattern.search(name+' '+email)),message_match=bool(pattern.search(msg)))
 commits.append(cs)
 if pattern.search(msg):matches.append(dict(kind='commit',id=sha,url=snapshot['repository']+'/-/commit/'+sha,matched_lines=textmatches(msg)))
assert len(commits)==len({c['sha'] for c in commits});assert sum(c['main'] for c in commits)==snapshot['main_commits']
mrrows=[]
for p in mrs:
 txt=p['title']+'\n'+(p['description'] or '')
 row=dict(iid=p['iid'],url=p['web_url'],title=p['title'],author_id=p['author']['id'],author=p['author']['username'],created=utc(p['created_at']),merged=utc(p['merged_at']) if p['merged_at'] else '',closed=utc(p['closed_at']) if p['closed_at'] else '',state=p['state'],target_branch=p['target_branch'],bot=bool(re.search(r'\[bot\]|^bot[-_]|[-_]bot$',p['author']['username'],re.I)),keyword_match=bool(pattern.search(txt)),claude_mention=bool(providers['claude'].search(txt)),codex_mention=bool(providers['codex'].search(txt)))
 mrrows.append(row)
 if row['keyword_match']:matches.append(dict(kind='merge request',id=str(p['iid']),url=p['web_url'],matched_lines=textmatches(txt)))
notes=load('notes.json.gz') if (D/'notes.json.gz').exists() else []
for n in notes:
 if pattern.search(n['body']):matches.append(dict(kind='comment',id=str(n['id']),url=f"{snapshot['repository']}/-/merge_requests/{n['iid']}#note_{n['id']}",matched_lines=textmatches(n['body'])))
write('keyword-matches.csv',matches,['kind','id','url','matched_lines'])
write('commits.csv',commits,list(commits[0]));write('merge-requests.csv',mrrows,list(mrrows[0]))
human=[r for r in mrrows if not r['bot']];first={}
for r in sorted(human,key=lambda r:r['created']):first.setdefault(r['author_id'],r['created'][:7])
monthly=[]
for y in range(2022,2027):
 for m in range(1,13):
  month=f'{y}-{m:02}';end=f'{y+(m==12)}-{m%12+1:02}-01'
  if month>'2026-10':continue
  opened=[r for r in human if r['created'].startswith(month)];merged=[r for r in human if r['merged'].startswith(month)];cs=[c for c in commits if c['main'] and c['date'].startswith(month)]
  monthly.append(dict(month=month,mrs_opened=len(opened),mrs_merged=len(merged),main_target_opened=sum(r['target_branch']=='main' for r in opened),main_target_merged=sum(r['target_branch']=='main' for r in merged),authors=len({r['author_id'] for r in opened}),first_time_authors=sum(v==month for v in first.values()),commits=len(cs),first_parent_commits=sum(c['first_parent'] for c in cs),claude_trailers=sum(c['claude_coauthor'] for c in cs),codex_trailers=sum(c['codex_coauthor'] for c in cs),combined_trailers=sum(c['claude_coauthor'] or c['codex_coauthor'] for c in cs),description_mentions=sum(r['claude_mention'] or r['codex_mention'] for r in opened),approx_open=sum(r['created'][:10]<end and (r['merged'] or r['closed'] or '9999')[:10]>=end for r in human)))
write('monthly.csv',monthly,list(monthly[0]))
annual=[]
for y in range(2022,2027):
 rs=[r for r in human if r['created'].startswith(str(y)) and int(r['created'][5:7])<=8];ms=[m for m in monthly if m['month'].startswith(str(y)) and int(m['month'][5:])<=8]
 annual.append(dict(year=y,mrs_opened=len(rs),mrs_merged=sum(m['mrs_merged'] for m in ms),authors=len({r['author_id'] for r in rs}),first_time_authors=sum(m['first_time_authors'] for m in ms),main_target_opened=sum(r['target_branch']=='main' for r in rs),main_target_merged=sum(m['main_target_merged'] for m in ms)))
write('jan-aug-comparison.csv',annual,list(annual[0]))
summary=dict(snapshot=snapshot,merge_requests=len(mrs),mr_states=dict(collections.Counter(r['state'] for r in mrrows)),target_branches=dict(collections.Counter(r['target_branch'] for r in mrrows)),authors=len({r['author_id'] for r in human}),bot_mrs=sum(r['bot'] for r in mrrows),main_commits=sum(c['main'] for c in commits),three_branch_unique_commits=len(commits),earliest_main_commit=min(c['date'] for c in commits if c['main']),claude_trailers=sum(c['claude_coauthor'] for c in commits),codex_trailers=sum(c['codex_coauthor'] for c in commits),ai_primary_authors=sum(c['ai_primary_author'] for c in commits),mr_keyword_matches=sum(r['keyword_match'] for r in mrrows),commit_keyword_matches=sum(c['message_match'] for c in commits),notes_searched=len(notes),matches=matches,jan_aug=annual,main_2026_commits=sum(c['main'] and c['date']>='2026-01-01' for c in commits),main_jan_aug_2026_commits=sum(c['main'] and '2026-01-01'<=c['date']<'2026-09-01' for c in commits))
(D/'summary.json').write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps(summary,indent=2))
files=sorted(p for p in D.iterdir() if p.suffix=='.gz' or p.name.endswith('-commits.txt') or p.name=='first-parent.txt')
(D/'SHA256SUMS').write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.name+'\n' for p in files))
