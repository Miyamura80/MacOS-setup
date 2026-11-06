# Objective-See security setup

The installer adds LuLu (outbound firewall), BlockBlock (persistence monitoring),
KnockKnock (persistence scanner), OverSight (mic/camera monitoring), ReiKey
(keyboard-tap monitoring), TaskExplorer, Netiquette, What's Your Sign, and
RansomWhere. These are the Objective-See tools available here through Homebrew;
this is not an exhaustive list of open-source macOS security software.
RansomWhere currently requires Rosetta on Apple Silicon and Full Disk Access.
Homebrew/installers may request administrator authorization.

## Activate protection

Open LuLu from Applications and complete its onboarding, including macOS approval
of its Network Extension and Network Filter. Finish BlockBlock's installer and
grant Full Disk Access to `/Library/Objective-See/BlockBlock/BlockBlock.app`.
Other tools have their own first-run permissions. Installing a cask alone does
not prove that its protection is active.

## LuLu rules for coding agents and curl

The installer prepares `security/lulu-developer-rules.local.json` for LuLu 4.5+.
It resolves native Codex, Claude Code, and OpenCode binaries on PATH and creates
**Allow / Process + Kids** rules, including their Python and curl children.
It also creates **Allow / Process** rules for system curl and the curl on PATH.
These allow connections to any destination; all code run by those agents gets
that network access. Shared Python, Node, Bun, shells, terminal apps, temporary
directories, and all of Homebrew are not given blanket exceptions.

LuLu's import replaces existing user rules. **On an existing installation,
export the current rules from LuLu's Rules menu first**, then merge them:

```sh
python3 security/prepare_lulu_rules.py \
  --existing "$HOME/Downloads/lulu-rules.json" \
  --output security/lulu-developer-rules.local.json
```

Use the actual name of your export. Keep that original export as a backup.
Review the generated JSON, then use LuLu's Rules > Import to import it. For a
fresh installation with no custom user rules, import the initially generated
file directly. The helper never changes LuLu's live rule database.

If an existing explicit Block rule still matches curl, Python, or an agent,
review and remove that conflicting rule in LuLu; a child-process allow rule
does not necessarily override a more specific rule. Rules apply to the active
LuLu profile, so import into the profile used for development.

For agents launched from a desktop app or a non-PATH location, pass the actual
native agent executable with `--agent /absolute/path/to/executable` (repeatable).
Check LuLu's alert process path/ancestry to find it. Script entrypoints are
skipped because the process is actually a shared interpreter. Prefer the native
CLI installs used by this repository. Regenerate and reimport after updates
that change executable paths, especially ad-hoc-signed Homebrew binaries.

Verify by asking the agent to run a curl request and a Python HTTPS request to
a known endpoint. Confirm those work and that LuLu remains enabled. Detached
children can lose their ancestry and require a separate, specific rule.

## BlockBlock and Python script execution

BlockBlock's persistence rules and its execution protections are separate.
For normal development use Settings > Protection with **Notarization enabled and its All option off**
(restrict notarization checks to downloaded programs). If generated Python
scripts still trigger execution alerts, turn off **Notarization** and
**Block (Downloaded) Scripts** in that pane for your development workflow.
This reduces execution protection globally, but leaves persistence monitoring
enabled. Keep BlockBlock enabled and its passive mode off.

There is no supported persistent per-agent exception for these execution modes:
execution approvals may be cached only until reboot/BlockBlock restart, depending
on mode and version. Recent downloaded-only modes may remove quarantine when an
item is allowed, so that item may not prompt again. With those protections
enabled, review any renewed execution alert after restart. A persistent Python-interpreter allow rule does not fix this.
The setup script does not pretend to install such a rule or edit BlockBlock's
private preference/rule files.

For intentional persistence changes (such as installing a LaunchAgent), inspect
the alert and use **Process + File + Item** to allow the exact operation. Avoid
allowing Python or a shell to perform every future persistence change.
KnockKnock is an on-demand scanner and does not block script execution.

Sources: [Objective-See tools](https://objective-see.org/tools.html),
[LuLu](https://objective-see.org/products/lulu.html),
[LuLu rule implementation](https://github.com/objective-see/LuLu/blob/master/LuLu/Shared/Rule.m),
[LuLu import implementation](https://github.com/objective-see/LuLu/blob/master/LuLu/Extension/Rules.m),
[BlockBlock](https://objective-see.org/products/blockblock.html),
[RansomWhere cask](https://formulae.brew.sh/cask/ransomwhere).
