"""Combine explicit Claude/Codex disclosures using a fixed snapshot, deduplicated by SHA."""
import csv,json,re,pathlib,gzip
D=pathlib.Path(__file__).resolve().parent/'data'
cs=list(csv.DictReader(open(D/'commits.csv')))
ps=json.loads(gzip.decompress((D/'pull_requests.json.gz').read_bytes()))
reviewed={int(r['number']):r for r in csv.DictReader(open(D/'pull-request-metadata.csv'))}
lookup={c['sha']:c for c in cs}; evidence={sha:{'claude':[],'codex':[]} for sha in lookup}
for sha,c in lookup.items():
 for provider,pattern in [('claude',r'claude|anthropic'),('codex',r'codex')]:
  if re.search(pattern,c['ai_trailers'],re.I):evidence[sha][provider].append('commit co-author trailer')
unmatched=[]
for p in ps:
 if not p['merged_at'] or reviewed[p['number']]['ai_disclosed']!='True':continue
 providers=[v for v in ['claude','codex'] if re.search(v,p['body'] or '',re.I)]
 if not providers:continue
 sha=p['merge_commit_sha']
 if sha not in lookup:
  unmatched.append(dict(number=p['number'],sha=sha,reason='Merge SHA not reachable in saved main history'));continue
 for provider in providers:evidence[sha][provider].append(p['html_url'])
def write(name,rows):
 with open(D/name,'w') as f:
  w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
audit=[]
for sha,e in evidence.items():
 if not any(e.values()):continue
 audit.append(dict(sha=sha,date=lookup[sha]['date'],claude=bool(e['claude']),codex=bool(e['codex']),claude_evidence=' | '.join(e['claude']),codex_evidence=' | '.join(e['codex'])))
write('combined-ai-commit-evidence.csv',audit)
monthly=[]
for m in sorted({c['date'][:7] for c in cs if c['date']>='2026-01-01'}):
 rs=[c for c in cs if c['date'].startswith(m)];es=[evidence[c['sha']] for c in rs]
 claude=sum(bool(e['claude']) and not e['codex'] for e in es);codex=sum(bool(e['codex']) and not e['claude'] for e in es);both=sum(bool(e['claude']) and bool(e['codex']) for e in es)
 monthly.append(dict(month=m,claude_only=claude,codex_only=codex,both=both,combined=claude+codex+both,total=len(rs),percent=100*(claude+codex+both)/len(rs)))
write('combined-ai-commit-share.csv',monthly)
(D/'unmatched-ai-prs.json').write_text(json.dumps(unmatched,indent=2))
print(json.dumps(monthly,indent=2));print('Unmatched:',unmatched)
