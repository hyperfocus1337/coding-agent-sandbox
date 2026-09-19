# cmux notifications

`just claude` and `just pi` pass one extra environment variable into the container:

```
docker exec -it -u user -e TERM_PROGRAM ...
```

That flag is what makes Claude pop up a desktop notification when it finishes a turn. Pi needs an extension as well; see [Pi](#pi) below. Both agents need you to start the recipe from a [cmux](https://cmux.com) terminal.

## Why cmux's own integration does not work here

On the host, cmux handles Claude Code with `cmux-claude-wrapper`. It is a fake `claude` on your `PATH` that starts the real one with extra hooks, and one of those hooks sends the notification by running `cmux`.

That does not work for `just claude`, for three reasons:

- The fake `claude` is on the host. We run `docker exec ... claude`, which finds the container's `claude` instead.
- The hooks call the `cmux` command, and `cmux` is a Mac program. There is no Linux version to put in the image.
- Even if there were, cmux only accepts connections from programs it started itself. Anything else gets `Error: ERROR: Access denied - only processes started inside cmux can connect`.

## What we do instead for Claude

Claude can send a notification on its own, by printing a special invisible sequence to the terminal. The cmux wrapper normally turns that off, because it would duplicate the notification the hooks already send. Since we get no hooks in the container, that built-in notification is all we have left, and it works fine: it is just terminal output, so it travels out of `docker exec` and cmux shows it.

Claude only uses it when it thinks it is running in Ghostty, which is the terminal cmux is built on. It checks two variables:

```js
isGhostty(){ return this.proc.env.TERM === "xterm-ghostty" || this.proc.env.TERM_PROGRAM === "ghostty" }
```

`docker exec` does not pass either one along, so inside the container both are empty, the check fails, and Claude decides it has no way to notify you. Passing `TERM_PROGRAM` in fixes it.

Two small details:

- We pass `TERM_PROGRAM` but not `TERM`. The container does not have the `xterm-ghostty` terminal definition installed, so setting `TERM` to it would garble Claude's interface.
- We write `-e TERM_PROGRAM` with no value. Docker then copies whatever the host has, or leaves it unset if the host has nothing. So outside cmux the flag simply does nothing.

## Pi

Pi sends no notification of its own, in any terminal. It ships one as an example extension, `examples/extensions/notify.ts` in the npm package. The extension listens for `agent_settled`, the event Pi fires when a run is finished and will not continue on its own, and writes an OSC 777 sequence:

```js
process.stdout.write(`\x1b]777;notify;${title};${body}\x07`);
```

That is the same kind of terminal output Claude uses, so it travels out of `docker exec` the same way and cmux renders it.

Pi loads no extension unless you ask for it, so `just pi` names the file:

```
pi --approve --extension /usr/local/share/npm-global/.../examples/extensions/notify.ts
```

Two differences from Claude:

- The extension does not check `TERM_PROGRAM`. It writes the sequence in every terminal. Terminals that do not know OSC 777 drop it, so there is nothing to see and nothing to clean up. `just pi` still passes `TERM_PROGRAM`, because Pi reads it to decide about images, true color and hyperlinks.
- Do not also put a copy of `notify.ts` in `~/.pi/agent/extensions/`. Pi would load both copies and send two notifications per turn.

## If notifications do not show up

The whole chain has to start in a cmux terminal. Run `just claude` or `just pi` from a normal terminal, or the VS Code terminal, and you get no notification, and nothing inside the container can fix that.

Check where you are:

```bash
env | grep -i cmux # expect CMUX_SURFACE_ID, CMUX_SOCKET_PATH, ...
echo $TERM_PROGRAM # expect ghostty
```

No output means you are not in cmux. Open a cmux pane and run the recipe there.

One thing not to do: do not add a `cmux notify` hook to your host `~/.claude/settings.json` to try to make up for this. cmux merges your hooks with its own instead of replacing them, so your hook and its hook both fire and you get two notifications for every turn on the host.
