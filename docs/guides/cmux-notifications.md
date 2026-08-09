# cmux notifications

`just claude` passes one extra environment variable into the container:

```
docker exec -it -u user -e TERM_PROGRAM ...
```

That flag is what makes Claude pop up a desktop notification when it finishes a turn. It only works if you started `just claude` from a [cmux](https://cmux.com) terminal.

## Why cmux's own integration does not work here

On the host, cmux handles Claude Code with `cmux-claude-wrapper`. It is a fake `claude` on your `PATH` that starts the real one with extra hooks, and one of those hooks sends the notification by running `cmux`.

That does not work for `just claude`, for three reasons:

- The fake `claude` is on the host. We run `docker exec ... claude`, which finds the container's `claude` instead.
- The hooks call the `cmux` command, and `cmux` is a Mac program. There is no Linux version to put in the image.
- Even if there were, cmux only accepts connections from programs it started itself. Anything else gets `Error: ERROR: Access denied - only processes started inside cmux can connect`.

## What we do instead

Claude can send a notification on its own, by printing a special invisible sequence to the terminal. The cmux wrapper normally turns that off, because it would duplicate the notification the hooks already send. Since we get no hooks in the container, that built-in notification is all we have left, and it works fine: it is just terminal output, so it travels out of `docker exec` and cmux shows it.

Claude only uses it when it thinks it is running in Ghostty, which is the terminal cmux is built on. It checks two variables:

```js
isGhostty(){ return this.proc.env.TERM === "xterm-ghostty" || this.proc.env.TERM_PROGRAM === "ghostty" }
```

`docker exec` does not pass either one along, so inside the container both are empty, the check fails, and Claude decides it has no way to notify you. Passing `TERM_PROGRAM` in fixes it.

Two small details:

- We pass `TERM_PROGRAM` but not `TERM`. The container does not have the `xterm-ghostty` terminal definition installed, so setting `TERM` to it would garble Claude's interface.
- We write `-e TERM_PROGRAM` with no value. Docker then copies whatever the host has, or leaves it unset if the host has nothing. So outside cmux the flag simply does nothing.

## If notifications do not show up

The whole chain has to start in a cmux terminal. Run `just claude` from a normal terminal, or the VS Code terminal, and you get no notification, and nothing inside the container can fix that.

Check where you are:

```bash
env | grep -i cmux # expect CMUX_SURFACE_ID, CMUX_SOCKET_PATH, ...
echo $TERM_PROGRAM # expect ghostty
```

No output means you are not in cmux. Open a cmux pane and run `just claude` there.

One thing not to do: do not add a `cmux notify` hook to your host `~/.claude/settings.json` to try to make up for this. cmux merges your hooks with its own instead of replacing them, so your hook and its hook both fire and you get two notifications for every turn on the host.
