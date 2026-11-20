# NAS Weather

Your home server's health as a weather report.

| Your machine | The weather |
|---|---|
| CPU temperature | Temperature |
| Load average | Wind |
| Disk space used | Cloud cover |
| NVMe temperature | Ground temp |
| RAID rebuild / reshape | Storm advisory, with a progress bar |
| Degraded array | Severe storm warning |
| Uptime | Clear streak |

You also get one forecast tile per drive bay, a 24-hour outlook built from your own schedule, and "what if" sliders (fail a drive, heat wave…).

**[Try the demo →](https://grayson.akerlyfam.com/lab/nas-weather)**

## Run it

You need Linux, bash and any static web server. No root, no dependencies.

```sh
git clone https://github.com/graysonx2/nas-weather
cd nas-weather
./collect.sh .                              # writes forecast.json + history.jsonl
python3 -m http.server 8090                 # or point nginx/caddy at this folder
```

Then add `collect.sh` to cron every 5 minutes:

```
*/5 * * * * /path/to/nas-weather/collect.sh /path/to/nas-weather
```

Open `http://<your-server>:8090`. If `forecast.json` is missing, the page shows sample data.

## Your schedule

Copy `schedule.example.json` to `schedule.json` and list when your machine is busy: backups, scans, transcodes. Each entry looks like this:

```json
{"name": "Nightly backup", "short": "Backup", "hours": [1], "minute": 0, "w": "rain"}
```

`w` picks the weather for that hour: `storm`, `rain`, `wind`, `fog` or `breeze`.

## Settings

| Env var | Default | |
|---|---|---|
| `VOLUME` | `/volume1`, falling back to `/` | Which mount counts as "cloud cover" |
| `HISTORY_DAYS` | `14` | How long `history.jsonl` is kept |

`./collect.sh --stdout` prints one reading and writes nothing, so you can check what it sees first.

## Limits

- **Drive temperatures** need `smartctl` and root, so they aren't read. CPU and NVMe temps come from `/sys/class/hwmon`.
- **RAID** means Linux software RAID (`/proc/mdstat`): Synology, UGREEN, most DIY boxes. ZFS isn't read yet.
- **Bays** come from the controller port in `/dev/disk/by-path`. On most NAS units that matches the bay number on the front, but check yours.
- Don't put this on the open internet as-is. A live page shows when your machine is busy, which can also show when you're home. Put it behind a login, or publish a snapshot.

## How it was made

This was a one-day "vibe-coded" side project, built with [Claude](https://claude.ai). The write-up is [on my site](https://grayson.akerlyfam.com/lab/nas-weather).

MIT licensed.
