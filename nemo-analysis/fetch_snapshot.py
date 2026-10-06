"""Fetch public NEMO GitLab merge requests. No credentials required."""
import argparse, concurrent.futures, datetime, gzip, json, pathlib, time, urllib.request, urllib.error
API='https://forge.nemo-ocean.eu/api/v4/projects/24'
def get(path):
 for attempt in range(4):
  try:
   with urllib.request.urlopen(urllib.request.Request(API+path,headers={'User-Agent':'NEMO-workshop-analysis'}),timeout=60) as r:
    return json.load(r),dict(r.headers)
  except urllib.error.HTTPError as e:
   if e.code in (401,403,404) or attempt==3:raise
   time.sleep(2**attempt)
  except Exception:
   if attempt==3:raise
   time.sleep(2**attempt)
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=pathlib.Path,required=True);a=p.parse_args()
 if (a.output/'merge_requests.json.gz').exists():raise SystemExit('Snapshot exists; choose another directory.')
 a.output.mkdir(parents=True,exist_ok=True)
 start=datetime.datetime.now(datetime.timezone.utc).isoformat()
 project,_=get('')
 def page(n):
  rows,h=get(f'/merge_requests?scope=all&state=all&per_page=100&page={n}&order_by=created_at&sort=asc')
  print(f'Page {n}: {len(rows)} records',flush=True);return rows,h
 first,h=page(1);pages=int(next(v for k,v in h.items() if k.lower()=='x-total-pages'))
 with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
  rest=list(pool.map(page,range(2,pages+1)))
 rows=first+[p for batch,_ in rest for p in batch]
 assert len(rows)==len({p['iid'] for p in rows})
 keys=['iid','title','description','state','created_at','updated_at','merged_at','closed_at','web_url','target_branch','source_branch','merge_commit_sha','squash_commit_sha','draft']
 out=[dict({k:r.get(k) for k in keys},author={k:r['author'].get(k) for k in ['id','username','name']}) for r in rows]
 (a.output/'merge_requests.json.gz').write_bytes(gzip.compress(json.dumps(out,ensure_ascii=False).encode(),mtime=0))
 meta=dict(repository=project['web_url'],default_branch=project['default_branch'],project_created_at=project['created_at'],public_merge_requests=len(rows),collection_started_utc=start,collection_finished_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),api_endpoint=API+'/merge_requests',pagination_pages=pages,first_page_reported_total=int(next(v for k,v in h.items() if k.lower()=='x-total')))
 (a.output/'snapshot.json').write_text(json.dumps(meta,indent=2)+'\n')
 print(json.dumps(meta,indent=2))
if __name__=='__main__':main()
