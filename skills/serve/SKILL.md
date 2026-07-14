---
name: serve
description: Use when the user wants to preview, share, expose, or test a local file, directory, project, or localhost over the public web — or to stop such a tunnel. Serves via a Python HTTP server and public ngrok tunnel.
argument-hint: <file-or-directory> [--port PORT]
allowed-tools: [Read, Bash, Glob]
user-invocable: true
---

Serve a local file or directory publicly over the web using Python's HTTP server and an ngrok tunnel.

## 1. Parse Arguments

`$ARGUMENTS` contains everything the user typed after `/serve`.

### Stop Command
If `$ARGUMENTS` is exactly `stop`:
- Kill the ngrok tunnel: `rtk pkill -f ngrok || true`
- Kill the HTTP server: `rtk pkill -f "http.server" || true`
- Wait 1 second for graceful shutdown
- Confirm: "✓ Server stopped. ngrok tunnel and HTTP server terminated."
- Stop processing and exit.

### Start Command
Otherwise, continue with the start flow:
- Extract the target path (file or directory). If omitted, use the current working directory.
- If the target is a single file (e.g. `glow-text.html`), serve its parent directory and remember the filename to append to the final URL.
- Extract an optional `--port PORT` flag. Default port: **8090**.
- Resolve any relative path to an absolute path.

## 2. Validate Target

- Confirm the target file or directory exists.
- If it does not exist, report the error and stop.

## 3. Kill Conflicting Processes

Check whether the port is already in use:
```bash
rtk lsof -i :<port>
```

Check whether ngrok is already running and serving the same port:
```bash
rtk curl -s http://127.0.0.1:4040/api/tunnels
```

- If an existing ngrok tunnel is already forwarding the target port, reuse it — extract and return the existing public URL without starting anything new.
- Otherwise, kill stale processes before starting fresh:
```bash
rtk pkill -f "http.server.*<port>" || true
rtk pkill -f ngrok || true
```

## 4. Resolve NGROK_AUTHTOKEN

1. Check `$NGROK_AUTHTOKEN` environment variable.
2. If unset, check `~/.config/ngrok/ngrok.yml` for an `authtoken` line.
3. If neither exists, ask the user for their token and instruct them to export `NGROK_AUTHTOKEN` before retrying. Stop here — do **not** hardcode or write the token to any file.

## 5. Start Local HTTP Server

```bash
rtk python3 -m http.server <port> --directory <target-directory> --bind 127.0.0.1 &
```

Wait ~2 seconds, then verify the server is up:
```bash
rtk curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:<port>/
```

If the response is not 200, report the error (likely a port conflict) and stop.

## 6. Start ngrok Tunnel

Always kill any existing ngrok processes first — stale processes may not respond to the API check in step 3 and will cause a 'multiple endpoints without pooling' error:
```bash
rtk pkill -f ngrok || true
```

Wait ~1 second for the process to exit, then launch:
```bash
NIXPKGS_ALLOW_UNFREE=1 rtk nix-shell -p ngrok --run "NGROK_AUTHTOKEN=$NGROK_AUTHTOKEN ngrok http <port>" &
```

`NIXPKGS_ALLOW_UNFREE=1` is required because ngrok is an unfree package in nixpkgs.

Wait ~8 seconds for ngrok to initialize and establish the tunnel.

## 7. Retrieve and Report Public URL

Query the ngrok local API:
```bash
rtk curl -s http://127.0.0.1:4040/api/tunnels
```

Parse `.tunnels[0].public_url` from the JSON response.

- If the original target was a specific file, append `/<filename>` to the URL.
- Report the full public URL to the user.

## 8. Error Handling

- **ngrok auth error**: Report the specific error from ngrok output and remind the user to set `NGROK_AUTHTOKEN`.
- **Port already bound**: Suggest retrying with `--port <alternative>`.
- **nix-shell cannot find ngrok**: Suggest ensuring nix is installed or using a pre-installed ngrok binary.

## Notes

- The ngrok free tier shows a browser interstitial on first visit — this is expected behavior.
- The tunnel stays alive as long as the ngrok process runs; it dies when the terminal session ends.
- To stop serving: Use `/serve stop` to cleanly terminate both the ngrok tunnel and HTTP server.

## Examples

| Command | Effect |
|---|---|
| `/serve` | Serves current working directory on port 8090 |
| `/serve glow-text.html` | Serves parent directory, URL points to the file |
| `/serve ./dist` | Serves the `dist` directory on port 8090 |
| `/serve index.html --port 3000` | Serves parent directory on port 3000 |
| `/serve stop` | Cleanly terminates the ngrok tunnel and HTTP server |
