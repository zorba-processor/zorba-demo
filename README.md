# zorba-demo

Ask questions in plain English about a folder of mixed-format files, and let
Claude answer them by writing JSONiq queries. The `data/` folder holds a frozen
snapshot of public geospatial feeds (earthquakes as GeoJSON, CSV and QuakeML,
disaster alerts as RSS/XML, satellite orbits as CSV and XML, weather as JSON,
a reference table as HTML). This repository configures
[zorba-mcp](https://zorba-processor.github.io/zorba/mcp.html), the MCP server
of the [Zorba](https://github.com/zorba-processor/zorba) query processor, so
that Claude can list those files and run queries over them, including queries
that join files of different formats. Nothing is converted or loaded first: each
query reads the files as they are.

## Requirements

- [Docker](https://docs.docker.com/get-docker/), running. The server runs from
  the image `ghcr.io/zorba-processor/zorba:5.0.0-alpha.1` (linux/amd64 and
  linux/arm64), pulled on first use.
- [Claude Code](https://code.claude.com/docs/en/overview) or
  [Claude Desktop](https://claude.ai/download), signed in with your own Claude
  account. This repository contains no API key and uses none.

## Quick start (Claude Code)

```sh
git clone https://github.com/zorba-processor/zorba-demo.git
cd zorba-demo
claude
```

Start `claude` from the repository root: the server mounts `data/` relative to
the project directory. On first start Claude Code asks whether to use the
project MCP server `zorba` defined in `.mcp.json`; approve it. `/mcp` shows
whether it is connected. Then ask one of the questions below, or your own.

The first start may take a little longer while Docker pulls the image; to pull
it beforehand, run `docker pull ghcr.io/zorba-processor/zorba:5.0.0-alpha.1`.

## Claude Desktop

Claude Desktop does not read `.mcp.json`. Add the server to
`claude_desktop_config.json` (Settings > Developer > Edit Config; on macOS it is
`~/Library/Application Support/Claude/claude_desktop_config.json`, on Windows
`%APPDATA%\Claude\claude_desktop_config.json`), replacing
`/absolute/path/to/zorba-demo` with the absolute path of your clone, then quit
and restart Claude Desktop:

```json
{
  "mcpServers": {
    "zorba": {
      "command": "docker",
      "args": [
        "run", "-i", "--rm", "--network", "none",
        "--mount", "type=bind,src=/absolute/path/to/zorba-demo/data,dst=/data,readonly",
        "ghcr.io/zorba-processor/zorba:5.0.0-alpha.1",
        "zorba-mcp", "--root", "/data"
      ]
    }
  }
}
```

## Questions to try

| # | Question | Formats | Expected answer |
|---|----------|---------|-----------------|
| 1 | Which earthquake in the USGS GeoJSON feed had the largest magnitude this week, and where was it? | GeoJSON | `us7000ttxz`, magnitude 6.4, southeast of Easter Island |
| 2 | Classify each tropical cyclone in the GDACS alert feed using the Saffir-Simpson table on the NHC page in the folder. | XML + HTML | VANCE-26 (138.9 km/h): category 1; IN-FA-26 (240.7 km/h): 4; ARNAB-26 (222.2 km/h): 4; FOUR-26 (120.4 km/h): 1 |
| 3 | For each city in `weather/cities.csv`, which magnitude 4.5+ earthquake from the GeoJSON feed was nearest, and how far away was it? | CSV + GeoJSON | 11 cities; for example Kupang: `us6000u4xp` at 41.8 km, Tokyo: `us7000ttt2` at 86.7 km, Anchorage: `us7000tu3j` at 1153 km |
| 4 | Which city has the highest current temperature in the weather files, and can every weather file be read? | JSON + CSV | Bushehr, 32.5 °C; `weather/anchorage.json` cannot be parsed |

The expected answers are the results of the queries in [`tests/`](tests/), one
`.jq` file per question with its exact definition (for example, which file
counts as "this week" and how distances are computed) and a `.expected` file
with its output. Claude writes its own queries, so a differently worded
question can lead to a different, still reasonable, interpretation.

Some differences between the files are deliberate: the three earthquake files
were fetched an hour apart, so they disagree the way copies of a live feed do,
and `weather/anchorage.json` is truncated on purpose. A query over all files
still runs: a file that does not parse comes back as a record with an `error`
member instead of its content.

## What the setup guarantees

These properties come from the [zorba-mcp documentation](https://zorba-processor.github.io/zorba/mcp.html#security)
and from the Docker command in `.mcp.json`:

- **Read-only.** Queries run under Zorba's secure policy: file writes and
  environment variables are denied. Independently, Docker mounts `data/`
  read-only.
- **Confined to `data/`.** Only `data/` is mounted into the container, and
  zorba-mcp limits reads to files under its root (`/data`): absolute paths,
  `..` segments and paths through symbolic links are rejected.
- **No network.** The policy denies `fn:doc` on URLs, the HTTP client, external
  XML entities and importing modules or schemas over the network. Independently,
  the container is started with `--network none`.
- **Limited native modules.** Importing native modules other than the file
  module (which the directory module reads through) is denied.
- **Bounded calls.** A tool call stops after 30 seconds and its output is cut at
  128 KiB (the zorba-mcp defaults).

## Checking the answers yourself

`tests/run.sh` starts the server with the exact command in `.mcp.json`, sends
each `tests/*.jq` query as a `run_query` call over JSON-RPC (as Claude does),
and compares the result with the `.expected` file. It needs Docker and `jq`.
The [Check](.github/workflows/check.yml) workflow runs it on every change, and
also checks that `.mcp.json` is valid JSON and pins the same image as this
README.

To run a query without an MCP client, use `zorba --directory`, which applies
the same policy:

```sh
docker run --rm --network none -v "$PWD:/work:ro" -w /work \
  ghcr.io/zorba-processor/zorba:5.0.0-alpha.1 --directory data -f -q tests/q1_largest_quake.jq
```

## Limitations

- `.mcp.json` mounts `${CLAUDE_PROJECT_DIR:-.}/data`. Claude Code sets
  `CLAUDE_PROJECT_DIR` only in the server's environment, not when it expands
  `.mcp.json`, so unless your shell exports that variable the mount resolves to
  `./data` in the directory `claude` was started in. Start it from the
  repository root. If the mount source does not exist, Docker stops with "bind
  source path does not exist" instead of mounting an empty folder.
- `--mount` does not accept a path containing a comma; clone into a path
  without one.
- The `.mcp.json` setup was tried with Claude Code on macOS; the Check workflow
  runs the same server command on Linux. On Windows, use the Claude Desktop
  snippet with an absolute path.
- `5.0.0-alpha.1` is a prerelease of Zorba 5.0.

## License

The files of this repository (configuration, documentation, queries and
scripts) are licensed under the [Apache License 2.0](LICENSE), like Zorba. The
data under `data/` is not covered by that license: each file stays under the
terms of its source, listed with attributions in
[`data/SOURCES.md`](data/SOURCES.md) (U.S. Geological Survey, GDACS, NASA
FIRMS, NOAA National Hurricane Center, CelesTrak, Open-Meteo under CC BY 4.0).
`data/SOURCES.md` was written for Zorba's agent benchmark; the files it lists
under `snapshot/` are the files directly under `data/` here, byte for byte
(the SHA-256 sums match).
