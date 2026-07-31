# Security policy

## Supported version

Only the latest public release receives security fixes.

## Reporting a vulnerability

Please use GitHub's private security advisory feature instead of opening a
public issue. Include reproduction steps, affected macOS and hardware versions,
and whether the problem requires Accessibility or Input Monitoring permission.

Do not include mouse serial numbers, local usernames, profile backups, or other
personal data.

## Security model

G502 Stage Mouse is a local menu bar application. It has no telemetry, account,
or cloud backend. It needs powerful macOS permissions to observe extra mouse
buttons and post system navigation events. The hover listener is passive and
the repository contains a regression script that rejects known dangerous event
patterns.

Public binaries are currently ad hoc signed and not notarized. For the strongest
trust boundary, review the source and build locally.
