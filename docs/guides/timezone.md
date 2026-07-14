# Timezone

The container timezone is controlled by the `TZ` build variable in the [`Justfile`](../../Justfile), which is passed as a build argument into [`Dockerfile.base`](../../Dockerfile.base) and exported as `ENV TZ`. The base image installs `tzdata`, so libc can resolve the named zone; without `tzdata` the `TZ` value is inert and everything falls back to UTC.

The default is `Europe/Amsterdam`, which is UTC+2 in summer (CEST) and UTC+1 in winter (CET) because it follows daylight saving time. If you want the wall clock to read UTC+2 during the summer half of the year, this is already the correct setting and no change is needed.

## Setting a fixed UTC+2 offset

If you want a constant UTC+2 all year with no DST shift, use the POSIX-style zone `Etc/GMT-2`. Note the sign is inverted in the `Etc/GMT*` names: `Etc/GMT-2` means UTC+2.

```bash
just TZ=Etc/GMT-2 build
```

## Changing the timezone at build time

`TZ` is baked into the image, so the clean way to change it is to rebuild with a different value. It also picks up `$TZ` from your shell environment if set.

```bash
just TZ=Europe/Amsterdam build     # +2 summer / +1 winter, DST-aware (default)
just TZ=Etc/GMT-2 build            # fixed +2 year-round
just TZ=UTC build                  # UTC
```

See the [building the images](building-images.md) guide for the full list of overridable variables.

## Changing the timezone without rebuilding

The devcontainer runs a prebuilt image pulled from GHCR, so a build-time change means rebuilding and pushing. To override the timezone on the image you already have, add `TZ` to the `environment:` block of the `sandbox` service in [`.devcontainer/docker-compose.yml`](../../.devcontainer/docker-compose.yml) and recreate the container:

```yaml
    environment:
      TZ: "Etc/GMT-2"
```

The runtime override still relies on `tzdata` being present in the image, which the base layer now installs. It does not persist into the image itself, so anyone building from source should set `TZ` at build time instead.

## Verifying

```bash
date
# e.g. Tue Jul 14 15:00:00 CEST 2026   (Europe/Amsterdam, summer)
# or   Tue Jul 14 15:00:00 +02   2026  (Etc/GMT-2)
```
