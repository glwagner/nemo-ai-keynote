"""Collect a new public PR snapshot, without overwriting the frozen analysis inputs."""
import argparse
import datetime
import gzip
import json
import os
from pathlib import Path
import urllib.request

FIELDS = ('number', 'html_url', 'title', 'body', 'created_at', 'merged_at',
          'closed_at', 'state', 'merge_commit_sha')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True,
                        help='New directory for this snapshot (must not exist)')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    started = datetime.datetime.now(datetime.timezone.utc).isoformat()
    headers = {'User-Agent': 'Oceananigans-workshop-analysis',
               'Accept': 'application/vnd.github+json'}
    if os.environ.get('GITHUB_TOKEN'):
        headers['Authorization'] = 'Bearer ' + os.environ['GITHUB_TOKEN']
    prs = []
    page = 1
    while True:
        url = ('https://api.github.com/repos/CliMA/Oceananigans.jl/pulls'
               f'?state=all&per_page=100&page={page}&sort=created&direction=desc')
        with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=60) as response:
            batch = json.load(response)
        for p in batch:
            record = {key: p[key] for key in FIELDS}
            record['user'] = {key: p['user'][key] for key in ('login', 'type')}
            prs.append(record)
        print(f'Fetched {len(prs)} PR records', flush=True)
        if len(batch) < 100:
            break
        page += 1
    if len(prs) != len({p['number'] for p in prs}):
        raise RuntimeError('Duplicate PR numbers: pagination moved during collection; retry a new snapshot.')
    payload = json.dumps(prs, ensure_ascii=False).encode()
    (args.output / 'pull_requests.json.gz').write_bytes(gzip.compress(payload, mtime=0))
    metadata = {'repository': 'https://github.com/CliMA/Oceananigans.jl',
                'collection_started_utc': started,
                'collection_finished_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                'prs': len(prs),
                'note': 'API pagination is not an atomic snapshot; PR descriptions remain editable.'}
    (args.output / 'pr-snapshot.json').write_text(json.dumps(metadata, indent=2) + '\n')


if __name__ == '__main__':
    main()
