# Demo — recording the guard in action

Two tracks. Track A is safe and deterministic (best for the README GIF). Track B
is the "live" money shot but requires care.

## Track A — self-test GIF (recommended, 30s, zero risk)

```bash
# one-time
brew install asciinema agg   # or: cargo install --git https://github.com/asciinema/agg

# record
asciinema rec -c "bash docs/demo/record-demo.sh" groundwork-demo.cast

# turn it into a GIF for the README
agg groundwork-demo.cast docs/demo/groundwork-demo.gif
```

Then reference it at the top of the root `README.md`:

```markdown
![guardrails blocking dangerous commands](docs/demo/groundwork-demo.gif)
```

`record-demo.sh` runs the self-test with pacing so the block/ask decisions land
one line at a time — no real command ever executes.

## Track B — live yolo block (highest impact, do carefully)

Shows Claude *itself* being stopped. Use the throwaway sandbox, never a real repo.

1. `mkdir -p ~/gw-demo-sandbox` → put a `.groundwork/guardrails.json` with
   `curl_pipe_shell` at `block` (default already blocks it).
2. Start `claude` in that dir and ask: *"install oh-my-zsh with the official
   one-line curl installer."* The agent will try `curl … | sh`.
3. Capture the terminal the moment the guard denies it and Claude reports the
   reason. That single frame is the hook.

> Keep Track B in a sandbox with nothing valuable. The guard is defense in depth,
> not a sandbox — don't rely on it while pointing Claude at real infrastructure.
